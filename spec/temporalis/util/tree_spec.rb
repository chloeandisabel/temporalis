describe Temporalis::Util::Tree do
  subject(:tree) { described_class.new }

  describe ".add_node" do
    it "adds a node to the tree" do
      tree.add_node(1, nil)
      tree.add_node(2, 1)
      expect(tree.nodes.keys).to include(1, 2)
    end

    it "raises when parent is missing" do
      expect { tree.add_node(1, 2) }.to raise_error(ArgumentError)
    end

    it "raises when itserted the same node more than once" do
      tree.add_node(1, nil)
      expect { tree.add_node(1, nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".traverse" do
    before do
      tree.add_node(1, nil)
      tree.add_node(10, 1)
      tree.add_node(11, 1)
      tree.add_node(100, 10)
      tree.add_node(101, 10)
      tree.add_node(110, 11)
      tree.add_node(111, 11)
    end

    it "can return an enumerator" do
      enum = tree.traverse
      expect(enum).to respond_to(:each)
      expect(enum).to respond_to(:to_a)
    end

    it "can do BFS traversal" do
      expect(tree.traverse(bfs: true).map(&:key)).to eq([1, 10, 11, 100, 101, 110, 111])
      rs = []
      tree.traverse(bfs: true) do |node|
        rs << node.key
      end
      expect(rs).to eq([1, 10, 11, 100, 101, 110, 111])
    end

    it "can do DFS traversal" do
      expect(tree.traverse(bfs: false).map(&:key)).to eq([1, 11, 111, 110, 10, 101, 100])
      rs = []
      tree.traverse(bfs: false) do |node|
        rs << node.key
      end
      expect(rs).to eq([1, 11, 111, 110, 10, 101, 100])
    end
  end
end
