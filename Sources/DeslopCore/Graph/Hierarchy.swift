import DeslopModel

/// How the lints walk the model's tree: up from a node, to where two
/// nodes meet, and how a node is named in reports.
public struct Hierarchy: Sendable {
    private let tree: Tree
    private let separator: String
    private let depths: [Int]

    public init(model: Model) {
        tree = model.tree
        separator = model.language.pathSeparator
        var depths: [Int] = []
        depths.reserveCapacity(tree.count)
        for id in tree.ids {
            depths.append(tree.parent(id).map { depths[$0.index] + 1 } ?? 0)
        }
        self.depths = depths
    }

    /// `id`, then its parent, up to the root.
    public func ancestors(_ id: NodeID) -> [NodeID] {
        var result: [NodeID] = []
        var at: NodeID? = id
        while let current = at {
            result.append(current)
            at = tree.parent(current)
        }
        return result
    }

    public func commonAncestor(_ first: NodeID, _ second: NodeID) -> NodeID {
        var a = first
        var b = second
        while depths[a.index] > depths[b.index], let up = tree.parent(a) { a = up }
        while depths[b.index] > depths[a.index], let up = tree.parent(b) { b = up }
        while a != b, let upA = tree.parent(a), let upB = tree.parent(b) {
            a = upA
            b = upB
        }
        return a
    }

    /// Whether `id` is `ancestor` or inside it; any node is inside a `nil` scope.
    public func isWithin(_ id: NodeID, _ ancestor: NodeID?) -> Bool {
        guard let ancestor else { return true }
        return ancestors(id).contains(ancestor)
    }

    /// The package `id` is in: itself, or its closest package ancestor.
    public func packageOf(_ id: NodeID) -> NodeID? {
        ancestors(id).first { tree.node($0).kind == .package }
    }

    public func isTest(_ id: NodeID) -> Bool {
        ancestors(id).contains { tree.node($0).test }
    }

    /// `package::module::child` for a module, `.` for the workspace, joined
    /// by the language's separator.
    public func display(_ id: NodeID) -> String {
        let current = tree.node(id)
        switch current.kind {
        case .workspace:
            return "."
        case .package:
            return current.name
        case .module:
            guard let up = current.parent else { return current.name }
            return display(up) + separator + current.name
        }
    }
}
