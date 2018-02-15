require "temporalis/active_record"
require "active_record"

describe Temporalis::ActiveRecord do
  def setup_db(db)
    ActiveRecord::Base.establish_connection(ENV.fetch("#{db.upcase}_DATABASE_URL"))

    ActiveRecord::Schema.define do
      create_table :temporalis_nodes, force: true do |t|
        t.integer :key, null: false
        t.datetime :valid_since, null: false
        t.datetime :valid_until, null: false
      end

      create_table :temporalis_node_closures, force: true do |t|
        t.integer :ancestor, null: false
        t.integer :descendant, null: false
        t.integer :level, null: false
        t.datetime :valid_since, null: false
        t.datetime :valid_until, null: false

        t.index [:ancestor]
        t.index [:descendant]
      end
    end
  end

  let(:node) do
    node_closure = self.node_closure

    Class.new(ActiveRecord::Base) do
      self.table_name = "temporalis_nodes"

      include Temporalis::ActiveRecord
      temporalis_tree closure_class: node_closure

      def self.name
        "TemporalisNode"
      end
    end
  end

  let(:node_closure) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "temporalis_node_closures"

      include Temporalis::ActiveRecord::Closure

      def self.name
        "TemporalisNodeClosure"
      end
    end
  end

  ENV.fetch("DATABASES_TO_TEST").split(",").each do |db|
    context "For database #{db}" do
      before(:all) do
        setup_db(db)
      end

      around(:each) do |e|
        node.transaction do
          e.run
          raise ActiveRecord::Rollback
        end
      end

      describe ".temporalis_add_node" do
        context "called without a parent" do
          it "creates a node record" do
            t = Time.current
            node.temporalis_add_node(t, 42, nil)
            expect(node.count).to eq(1)
            n = node.last
            expect(n.key).to eq(42)
            expect(n.valid_since).to be_within(1.second).of(t)
            expect(n.valid_until).to be > Time.current
          end
        end

        context "called with parent_key" do
          it "creates a node record" do
            t = Time.current
            node.temporalis_add_node(t, 42, nil)
            node.temporalis_add_node(t, 43, 42)
            expect(node.count).to eq(2)
            n = node.with_key(42).first
            n2 = node.with_key(43).first
            expect(n).to be_present
            expect(n2).to be_present
          end

          it "creates node closures for the whole parent chain" do
            t = Time.current
            node.temporalis_add_node(t, 100, nil)
            node.temporalis_add_node(t, 101, 100)
            node.temporalis_add_node(t, 102, 101)

            ancestors = node_closure.active_at(t).ancestors_of(102).order(:level)
            expect(ancestors.count).to eq(2)
            expect(ancestors.map(&:ancestor)).to eq([101, 100])
            expect(ancestors.map(&:valid_since)).to all(be_within(1.second).of(t))
            descendants = node_closure.active_at(t).descendants_of(100).order(:level)
            expect(descendants.count).to eq(2)
            expect(descendants.map(&:descendant)).to eq([101, 102])
            expect(descendants.map(&:valid_since)).to all(be_within(1.second).of(t))
          end
        end

        describe ".temporalis_implode_node" do
          it "expires the node record" do
            t = Time.current
            node.temporalis_add_node(t - 1.second, 42, nil)
            node.temporalis_implode_node(t, 42)
            n = node.with_key(42).first
            expect(n.valid_until).to be_within(1.second).of(t)
          end

          it "expires the ancestors and descendant closures" do
            t = Time.current
            node.temporalis_add_node(t - 1.second, 100, nil)
            node.temporalis_add_node(t - 1.second, 101, 100)
            node.temporalis_add_node(t - 1.second, 102, 101)
            node.temporalis_add_node(t - 1.second, 103, 101)

            node.temporalis_implode_node(t, 101)
            ancestors = node_closure.active_at(t - 1.second).ancestors_of(101)
            descendants = node_closure.active_at(t - 1.second).descendants_of(101)
            expect(ancestors.map(&:valid_until)).to all(be_within(1.second).of(t))
            expect(descendants.map(&:valid_until)).to all(be_within(1.second).of(t))
          end

          it "expires the descendant closures for imploded node ancestors" do
            t = Time.current
            node.temporalis_add_node(t - 1.second, 100, nil)
            node.temporalis_add_node(t - 1.second, 101, 100)
            node.temporalis_add_node(t - 1.second, 102, 101)
            node.temporalis_add_node(t - 1.second, 103, 101)

            node.temporalis_implode_node(t, 101)
            closures = node_closure.active_at(t - 1.second).ancestors_of([102, 103])
            expect(closures.map(&:valid_until)).to all(be_within(1.second).of(t))
          end

          it "creates new descendant closures for imploded node ancestors" do
            t = Time.current
            node.temporalis_add_node(t - 1.second, 100, nil)
            node.temporalis_add_node(t - 1.second, 101, 100)
            node.temporalis_add_node(t - 1.second, 102, 101)
            node.temporalis_add_node(t - 1.second, 103, 101)

            node.temporalis_implode_node(t, 101)
            closures = node_closure.active_at(t).ancestors_of([103])
            expect(closures.map(&:ancestor)).to eq([100])
            expect(closures.map(&:valid_until)).to all(be > Time.current)
          end
        end
      end

      describe ".temporalis_change_parent" do
        let(:timestamp) { Time.current }

        before(:each) do
          # Initial tree:
          # 100
          #  | \
          # 101 102
          #  | \
          # 110 111
          #  |
          # 120
          node.temporalis_add_node(timestamp - 1.second, 100, nil)
          node.temporalis_add_node(timestamp - 1.second, 101, 100)
          node.temporalis_add_node(timestamp - 1.second, 102, 100)
          node.temporalis_add_node(timestamp - 1.second, 110, 101)
          node.temporalis_add_node(timestamp - 1.second, 111, 101)
          node.temporalis_add_node(timestamp - 1.second, 120, 110)
        end

        it "expires the parent closures of the moved node" do
          node.temporalis_change_parent(timestamp, 110, 102)
          closures = node_closure.active_at(timestamp - 1.second).ancestors_of(110)
          expect(closures.map(&:valid_until)).to all(be_within(1.second).of(timestamp))
        end

        it "expires the descendant closures for the ancestors of the moved node" do
          node.temporalis_change_parent(timestamp, 110, 102)
          # 110 is the immediate ancestor, and its closure will not change
          closures = node_closure.active_at(timestamp - 1.second).ancestors_of(120).where.not(ancestor: 110)
          expect(closures.map(&:valid_until)).to all(be_within(1.second).of(timestamp))
        end

        it "creates new ancestor closures for the moved node" do
          node.temporalis_change_parent(timestamp, 110, 102)
          closures = node_closure.active_at(timestamp).ancestors_of(110).order(:level)
          expect(closures.map(&:valid_until)).to all(be > Time.current)
          expect(closures.map(&:ancestor)).to eq([102, 100])
        end

        it "creates new ancestor closures for the descendants of the moved node" do
          node.temporalis_change_parent(timestamp, 110, 102)
          closures = node_closure.active_at(timestamp).ancestors_of(120).order(:level)
          expect(closures.map(&:valid_until)).to all(be > Time.current)
          expect(closures.map(&:ancestor)).to eq([110, 102, 100])
        end
      end

      describe ".temporalis_ancestors / .temporalis_descendants tests" do
        let(:timestamp) { Time.current }

        it "works for the current tree" do
          node.temporalis_add_node(timestamp, 100, nil)
          node.temporalis_add_node(timestamp, 101, 100)
          node.temporalis_add_node(timestamp, 102, 100)
          node.temporalis_add_node(timestamp, 110, 101)
          node.temporalis_add_node(timestamp, 111, 101)
          node.temporalis_add_node(timestamp, 120, 102)
          node.temporalis_add_node(timestamp, 121, 102)

          expect(node.temporalis_ancestors(timestamp, 100)).to eq([])
          expect(node.temporalis_ancestors(timestamp, 101)).to eq([100])
          expect(node.temporalis_ancestors(timestamp, 102)).to eq([100])
          expect(node.temporalis_ancestors(timestamp, 110)).to eq([101, 100])
          expect(node.temporalis_ancestors(timestamp, 111)).to eq([101, 100])
          expect(node.temporalis_ancestors(timestamp, 120)).to eq([102, 100])
          expect(node.temporalis_ancestors(timestamp, 121)).to eq([102, 100])

          expect(node.temporalis_descendants(timestamp, 100)).to match_array([101, 102, 110, 111, 120, 121])
          expect(node.temporalis_descendants(timestamp, 101)).to match_array([110, 111])
          expect(node.temporalis_descendants(timestamp, 102)).to match_array([120, 121])
          expect(node.temporalis_descendants(timestamp, 110)).to match_array([])
          expect(node.temporalis_descendants(timestamp, 111)).to match_array([])
          expect(node.temporalis_descendants(timestamp, 120)).to match_array([])
          expect(node.temporalis_descendants(timestamp, 121)).to match_array([])
        end

        it "correctly indicates historical state after the tree changes" do
          future_timestamp = timestamp + 1.second

          node.temporalis_add_node(timestamp, 100, nil)
          node.temporalis_add_node(timestamp, 101, 100)
          node.temporalis_add_node(timestamp, 102, 100)
          node.temporalis_add_node(timestamp, 110, 101)
          node.temporalis_add_node(timestamp, 111, 101)
          node.temporalis_add_node(timestamp, 120, 102)
          node.temporalis_add_node(timestamp, 121, 102)

          node.change_parent(future_timestamp, 120, 101)

          expect(node.temporalis_ancestors(timestamp, 100)).to eq([])
          expect(node.temporalis_ancestors(timestamp, 101)).to eq([100])
          expect(node.temporalis_ancestors(timestamp, 102)).to eq([100])
          expect(node.temporalis_ancestors(timestamp, 110)).to eq([101, 100])
          expect(node.temporalis_ancestors(timestamp, 111)).to eq([101, 100])
          expect(node.temporalis_ancestors(timestamp, 120)).to eq([102, 100])
          expect(node.temporalis_ancestors(timestamp, 121)).to eq([102, 100])

          expect(node.temporalis_descendants(timestamp, 100)).to match_array([101, 102, 110, 111, 120, 121])
          expect(node.temporalis_descendants(timestamp, 101)).to match_array([110, 111])
          expect(node.temporalis_descendants(timestamp, 102)).to match_array([120, 121])
          expect(node.temporalis_descendants(timestamp, 110)).to match_array([])
          expect(node.temporalis_descendants(timestamp, 111)).to match_array([])
          expect(node.temporalis_descendants(timestamp, 120)).to match_array([])
          expect(node.temporalis_descendants(timestamp, 121)).to match_array([])
        end
      end

      describe ".temporalis_batch_add_nodes" do
        let(:timestamp) { Time.current }
        it "allows inserting multiple nodes in one query" do
          node.temporalis_batch_add_nodes(timestamp, [[1, nil], [10, 1], [11, 1], [100, 10], [101, 10], [110, 11], [111, 11]])

          expect(node.count).to eq(7)
          expect(node.temporalis_ancestors(timestamp, 100)).to eq([10, 1])
          expect(node.temporalis_ancestors(timestamp, 111)).to eq([11, 1])
          expect(node.temporalis_descendants(timestamp, 1)).to match_array([10, 11, 100, 101, 110, 111])
          expect(node.temporalis_descendants(timestamp, 10)).to match_array([100, 101])
        end
      end
    end
  end
end
