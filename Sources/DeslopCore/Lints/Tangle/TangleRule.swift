import DeslopModel

/// `tangle`: things that know each other in a circle, written in more than
/// one module, or more of them than a reader holds in mind. Where a tangle
/// is written is its members' homes and the modules of the references that
/// tie it, so moving an extension or lifting a member into the parent
/// module changes nothing.
public struct TangleRule: LintRule {
    private struct Written {
        var modules: Set<NodeID>
        var ties = Ties<ThingID>()
    }

    public init() {}

    public func check(_ context: LintContext) -> [Diagnostic] {
        let graph = context.graph
        let tangles = graph.tangleIDs
        var written = tangles.map { tangle in
            Written(modules: Set(graph.members(of: tangle).map { graph.thing($0).home }))
        }
        for usage in graph.uses {
            guard let user = usage.user, let used = graph.thing(of: usage.item) else { continue }
            guard user != used, let tangle = graph.tangle(of: user), graph.tangle(of: used) == tangle else {
                continue
            }
            let reference = context.model.references[usage.reference]
            written[tangle.index].modules.insert(reference.from)
            written[tangle.index].ties.add(
                context, user: user, used: used, item: usage.item, reference: reference, module: reference.from
            )
        }
        var diagnostics: [Diagnostic] = []
        for (index, found) in written.enumerated() {
            let members = graph.members(of: tangles[index])
            let concerned = members.contains { context.hierarchy.isWithin(graph.thing($0).home, context.scope) }
            if concerned && (found.modules.count > 1 || members.count > Text.heldInMind) {
                diagnostics.append(diagnostic(context, members: members, written: found))
            }
        }
        return diagnostics
    }

    private func diagnostic(_ context: LintContext, members: [ThingID], written: Written) -> Diagnostic {
        let names = Text.sorted(members.map { Text.fullName($0, context) })
        let ties = written.ties.sorted.map {
            CircleReport.Named(user: Text.fullName($0.key.user, context), used: Text.fullName($0.key.used, context), tie: $0.tie)
        }
        let report = CircleReport(context, verb: "knows", noun: "thing", members: members.count, ties: ties)
        var notes = ["members: \(Text.listed(names))"]
        if written.modules.count > 1 {
            let modules = Text.sorted(written.modules.map(context.hierarchy.display))
            notes.append("written in: \(Text.listed(modules))")
        }
        notes += report.notes
        let message: String
        if written.modules.count == 1, let only = written.modules.first {
            message = "\(names.count) things know each other in a circle, all in `\(context.hierarchy.display(only))`"
        } else {
            message = "\(names.count) things know each other in a circle, across \(Text.counted(written.modules.count, "module"))"
        }
        return Diagnostic(
            lint: .tangle,
            key: names.joined(separator: ","),
            message: message,
            location: report.location,
            notes: notes,
            picture: report.picture
        )
    }
}
