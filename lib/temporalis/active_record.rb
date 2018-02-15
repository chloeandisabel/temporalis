require "active_record"
require "activerecord-import"

module Temporalis
  END_OF_TIME_DEFAULT = Time.utc(2100, 1, 1)

  module ActiveRecord
    module Closure
      def self.included(receiver)
        receiver.class_eval do
          scope :active_at, -> (timestamp) {
            where("valid_since <= ? AND valid_until > ?", timestamp, timestamp)
          }

          scope :descendants_of, -> (key) {
            where(ancestor: key)
          }

          scope :ancestors_of, -> (key) {
            where(descendant: key)
          }
        end
      end
    end

    module ClassMethods
      attr_reader :temporalis_closure_class, :temporalis_end_of_time

      def temporalis_tree(closure_class_name: nil, closure_class: nil, use_unprefixed_aliases: true, end_of_time: Temporalis::END_OF_TIME_DEFAULT)
        @temporalis_closure_class = closure_class || (closure_class_name || "#{name}Closure").constantize
        @temporalis_end_of_time = end_of_time

        if use_unprefixed_aliases
          mod = Module.new do
            [:ancestors, :descendants, :add_node, :implode_node, :change_parent, :batch_add_nodes].each do |method|
              define_method(method) do |*args, &block|
                public_send("temporalis_#{method}", *args, &block)
              end
            end
          end

          extend mod
        end

        scope :with_key, -> (key) { where(key: key) }
        scope :active_at, -> (timestamp) { where("valid_since <= ? AND valid_until > ?", timestamp, timestamp) }
      end

      def temporalis_add_node(timestamp, key, parent_key, valid_until: nil)
        fail ArgumentError, "node #{key} is already active at #{timestamp}" if active_at(timestamp).with_key(key).any?

        valid_until ||= temporalis_end_of_time
        columns = [:ancestor, :descendant, :level, :valid_since, :valid_until]
        new_closures = temporalis_closure_class
                        .ancestors_of(parent_key)
                        .active_at(timestamp)
                        .pluck(:ancestor, :level, :valid_until)
                        .map do |ancestor, level, valid_until|
                          [ancestor, key, level + 1, timestamp, valid_until]
                        end
        new_closures += [[parent_key, key, 1, timestamp, valid_until]] if parent_key


        transaction do
          create!(key: key, valid_since: timestamp, valid_until: valid_until)
          temporalis_closure_class.import(columns, new_closures, validate: false)
        end
      end

      def temporalis_batch_add_nodes(timestamp, tuples, valid_until: nil)
        valid_until ||= temporalis_end_of_time

        tree = Util::Tree.new do |tree|
          tuples.each do |key, parent_key|
            tree.add_node(key, parent_key)
          end
        end

        ancestors = {}
        nodes = []
        closures = []
        tree.traverse do |node|
          nodes << node
          ancestors[node] = [*node.parent.key, *ancestors[node.parent]]
          closures.concat ancestors[node].each_with_index.map { |parent_key, i| [parent_key, node.key, i + 1] }
        end
        transaction do
          import(
            [:key, :valid_since, :valid_until],
            nodes.map { |node| [node.key, timestamp, valid_until] },
            validate: false
          )

          temporalis_closure_class.import(
            [:ancestor, :descendant, :level, :valid_since, :valid_until],
            closures.map { |ancestor, descendant, level| [ancestor, descendant, level, timestamp, valid_until] },
            validate: false
          )
        end
      end

      def temporalis_implode_node(timestamp, key)
        # Let's say we have a tree of
        # 1 -> 2 -> 3, 4
        # And we are imploding node 2
        # Then ancestors are closures (1->2 level 1)
        # And descendants are closures (2->3 level 1 and 2->4 level 1)
        # And descendants_for_ancestors are closures (1->3 level 2 and 1->4 level 2)
        # We need to update valid_until for ancestors and descendants
        # And we need to insert new descendants_for_ancestors with level = level - 1
        ancestors = temporalis_closure_class
                      .ancestors_of(key)
                      .active_at(timestamp)

        descendants = temporalis_closure_class
                        .descendants_of(key)
                        .active_at(timestamp)

        descendants_for_ancestors = temporalis_closure_class
                                      .descendants_of(ancestors.pluck(:ancestor))
                                      .ancestors_of(descendants.pluck(:descendant))
                                      .active_at(timestamp)

        columns = [:ancestor, :descendant, :level, :valid_since, :valid_until]
        new_descendants_for_ancestors = descendants_for_ancestors.pluck(*columns).map do |ancestor, descendant, level, valid_since, valid_until|
          [ancestor, descendant, level - 1, timestamp, valid_until]
        end

        transaction do
          ancestors.update_all(valid_until: timestamp)
          descendants.update_all(valid_until: timestamp)
          descendants_for_ancestors.update_all(valid_until: timestamp)
          temporalis_closure_class.import(columns, new_descendants_for_ancestors, validate: false)
          active_at(timestamp).with_key(key).update_all(valid_until: timestamp)
        end
      end

      def temporalis_change_parent(timestamp, key, new_parent_key)
        # Let's say we have a tree of
        # 1 -> 2 -> 3, 4
        # 1 -> 5
        # And we are changing parent of (2) from (1) to (5)
        # Then ancestors are closures (1->2 level 1)
        # And descendants are closures (2->3 level 1 and 2->4 level 1)
        # And descendants_for_ancestors are closures (1->3 level 2 and 1->4 level 2)
        # And ancestors_for_new_parent are closures (1->5 level 1)
        #
        # We need to update valid_until for ancestors, descendants and descendants_for_ancestors
        # And we need to insert new closures for each descendant for each new parent with level = descendant_level + parent_ancestor_level
        # And new closures for each new parent for the switching node
        ancestors = temporalis_closure_class
                      .ancestors_of(key)
                      .active_at(timestamp)

        descendants = temporalis_closure_class
                        .descendants_of(key)
                        .active_at(timestamp)

        old_descendant_ancestors = temporalis_closure_class
                                     .ancestors_of(descendants.pluck(:descendant))
                                     .descendants_of(ancestors.pluck(:ancestor))
                                     .active_at(timestamp)

        new_parent_ancestors = temporalis_closure_class
                                 .ancestors_of(new_parent_key)
                                 .active_at(timestamp)

        columns = [:ancestor, :descendant, :level, :valid_since, :valid_until]
        descendant_data = descendants.pluck(*columns)
        new_closures = new_parent_ancestors.pluck(*columns).flat_map do |a_ancestor, a_descendant, a_level, a_valid_since, a_valid_until|
          [[a_ancestor, key, a_level + 1, timestamp, temporalis_end_of_time]] +
            descendant_data.map do |d_ancestor, d_descendant, d_level, d_valid_since, d_valid_until|
              [a_ancestor, d_descendant, a_level + d_level + 1, timestamp, temporalis_end_of_time]
            end
        end
        new_closures.concat [[new_parent_key, key, 1, timestamp, temporalis_end_of_time]]
        new_closures.concat descendant_data.map { |ancestor, descendant, level, valid_since, valid_until| [new_parent_key, descendant, level + 1, timestamp, temporalis_end_of_time] }

        transaction do
          ancestors.update_all(valid_until: timestamp)
          old_descendant_ancestors.update_all(valid_until: timestamp)
          temporalis_closure_class.import(columns, new_closures, validate: false)
        end
      end

      def temporalis_ancestors(timestamp, key)
        temporalis_closure_class
          .ancestors_of(key)
          .active_at(timestamp)
          .order(:level)
          .pluck(:ancestor)
      end

      def temporalis_descendants(timestamp, key)
        temporalis_closure_class
          .descendants_of(key)
          .active_at(timestamp)
          .pluck(:descendant)
      end
    end

    def self.included(receiver)
      receiver.extend ClassMethods
    end
  end
end
