/// The hierarchy: the workspace, its packages, and their modules. The first
/// node is the workspace; each other node comes after its parent. How the
/// lints walk it is theirs to say; the tree only holds its nodes.
public struct Tree: Sendable {
    private struct ChildKey: Hashable, Sendable {
        let parent: NodeID
        let kind: NodeKind
        let name: String
    }

    /// The workspace, the first node of every tree.
    public static let root = NodeID(0)

    public private(set) var nodes: [Node]
    private var children: [ChildKey: NodeID]

    /// A tree with only the workspace.
    public init() {
        nodes = [Node(name: "", kind: .workspace, parent: nil, test: false)]
        children = [:]
    }

    /// A tree of `nodes`, which must already satisfy the tree's invariants:
    /// the first is the only one without a parent, and each parent precedes
    /// its children. `ModelCodec` checks them.
    init(validatedNodes nodes: [Node]) {
        self.nodes = nodes
        children = [:]
        for (index, node) in nodes.enumerated() {
            if let parent = node.parent {
                children[ChildKey(parent: parent, kind: node.kind, name: node.name)] = NodeID(index)
            }
        }
    }

    /// How many nodes it has.
    public var count: Int { nodes.count }

    /// Every node, each after its parent.
    public var ids: [NodeID] { nodes.indices.map(NodeID.init) }

    /// The child of `parent` with this kind and name, made if it is new.
    public mutating func child(of parent: NodeID, kind: NodeKind, name: String) -> NodeID {
        let key = ChildKey(parent: parent, kind: kind, name: name)
        if let known = children[key] {
            return known
        }
        let id = NodeID(nodes.count)
        nodes.append(Node(name: name, kind: kind, parent: parent, test: false))
        children[key] = id
        return id
    }

    public func node(_ id: NodeID) -> Node {
        nodes[id.index]
    }

    public func parent(_ id: NodeID) -> NodeID? {
        nodes[id.index].parent
    }

    /// Marks `id` as test code, and so everything inside it.
    public mutating func setTest(_ id: NodeID, _ test: Bool) {
        nodes[id.index].test = test
    }
}
