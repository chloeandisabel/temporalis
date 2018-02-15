module Temporalis
  module Util
    class Tree
      class Node
        attr_reader :key, :parent, :children
        def initialize(key, parent)
          @key = key
          @parent = parent
          @children = []
        end
      end

      attr_reader :root, :nodes
      def initialize(&block)
        @root = Node.new(nil, nil)
        @nodes = { nil => root }
        yield self if block_given?
      end

      def traverse(bfs: true, &block)
        return to_enum(__method__, bfs: bfs) unless block_given?

        queue = [root]
        while queue.any?
          node = bfs ? queue.shift : queue.pop
          yield node unless node.key.nil?
          queue.concat(node.children)
        end
      end

      def add_node(key, parent_key)
        fail ArgumentError, "node with key #{key} had already been added" if nodes.key?(key)
        parent_node = nodes.fetch(parent_key) { fail ArgumentError, "Node with key #{key.inspect} is not in the tree" }
        nodes[key] = Node.new(key, parent_node)
        parent_node.children << nodes[key]
      end
    end
  end
end
