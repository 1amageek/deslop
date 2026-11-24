import DeslopModel

/// `module-cycle`: sibling modules that use each other in a circle, so there
/// is no order to read them in. A module uses a sibling when code written in
/// it or inside it names an item written in the sibling or inside it. What a
/// module and the modules inside it use of each other makes no circle, and
/// neither do packages, which their build keeps in order.
public struct ModuleCycleRule: LintRule {
    public init() {}

    public func check(_ context: LintContext) -> [Diagnostic] {
        let model = context.model
        let tree = model.tree
        let hierarchy = context.hierarchy
        // By parent, the ties between its children.
        var byParent: [NodeID: Ties<NodeID>] = [:]
        for reference in model.references where !reference.test {
            let item = model.item(reference.item)
            let inTestFile = item.file.map { model.file($0).test } ?? false
            if item.kind == .module || hierarchy.isTest(item.owner) || inTestFile { continue }
            guard let (parent, user, used) = siblings(tree, hierarchy, reference.from, item.owner) else { continue }
            byParent[parent, default: Ties()].add(
                context, user: user, used: used, item: reference.item, reference: reference, module: user
            )
        }
        var diagnostics: [Diagnostic] = []
        for (parent, ties) in byParent.sorted(by: { $0.key < $1.key }) {
            let keys = ties.sorted.map(\.key)
            let children = Array(Set(keys.flatMap { [$0.user, $0.used] })).sorted()
            let place = Dictionary(uniqueKeysWithValues: children.enumerated().map { ($1, $0) })
            var uses = [[Int]](repeating: [], count: children.count)
            for key in keys {
                guard let user = place[key.user], let used = place[key.used] else {
                    preconditionFailure("every tied module is one of the children it was gathered from")
                }
                uses[user].append(used)
            }
            for circle in StronglyConnectedComponents.circles(uses) {
                let members = circle.map { children[$0] }
                if members.contains(where: { hierarchy.isWithin($0, context.scope) }) {
                    diagnostics.append(diagnostic(context, parent: parent, members: members, ties: ties))
                }
            }
        }
        return diagnostics
    }

    /// The module that holds both `a` and `b`, and its children that hold
    /// each, unless one of the two holds the other or they are in different packages.
    private func siblings(_ tree: Tree, _ hierarchy: Hierarchy, _ a: NodeID, _ b: NodeID) -> (NodeID, NodeID, NodeID)? {
        let parent = hierarchy.commonAncestor(a, b)
        if parent == a || parent == b || tree.node(parent).kind == .workspace {
            return nil
        }
        func child(_ of: NodeID) -> NodeID? {
            hierarchy.ancestors(of).first { tree.parent($0) == parent }
        }
        guard let first = child(a), let second = child(b) else { return nil }
        return (parent, first, second)
    }

    private func diagnostic(_ context: LintContext, parent: NodeID, members: [NodeID], ties: Ties<NodeID>) -> Diagnostic {
        let tree = context.model.tree
        let name = { (module: NodeID) in tree.node(module).name }
        let names = Text.sorted(members.map(name))
        let keys = Text.sorted(members.map(context.hierarchy.display))
        let inside = ties.sorted
            .filter { members.contains($0.key.user) && members.contains($0.key.used) }
            .map {
                CircleReport.Named(
                    user: name($0.key.user), used: name($0.key.used),
                    userIdentity: $0.key.user.index, usedIdentity: $0.key.used.index, tie: $0.tie
                )
            }
        let report = CircleReport(context, verb: "uses", noun: "module", members: members.count, ties: inside)
        return Diagnostic(
            lint: .moduleCycle,
            key: keys.joined(separator: ","),
            message: "\(Text.counted(members.count, "module")) in `\(context.hierarchy.display(parent))` use each other in a circle",
            location: report.location,
            notes: ["members: \(Text.listed(names))"] + report.notes,
            picture: report.picture
        )
    }
}
