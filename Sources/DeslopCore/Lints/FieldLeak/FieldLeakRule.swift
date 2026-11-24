import DeslopModel

/// `field-leak`: code that works on a field of a type it is not part of. A
/// type guards its fields when it keeps at least one of them to itself and
/// has a method of its own that takes `self`, not a wrapper, that uses them.
/// A marker field holds nothing to keep and plays no part. Then each of its
/// fields that an outsider writes, reaches into, or calls a method on,
/// directly or through a getter or setter, is known outside it. Reading a
/// value is no leak, with or without a getter. Neither is calling a method
/// that passes the call on to a field, whose callers never see the field.
/// Its insiders are its own definition and methods, wherever they are
/// written, the things in its tangle, and the types that inherit its
/// implementation, such as its subclasses: how a type is extended by
/// inheritance is its developers' choice. Visibility keywords play no part.
public struct FieldLeakRule: LintRule {
    public init() {}

    public func check(_ context: LintContext) -> [Diagnostic] {
        let model = context.model
        let graph = context.graph
        var fields: [ThingID: [ItemID]] = [:]
        for (index, item) in model.items.enumerated() {
            let ofType = item.parent.map { model.item($0).kind == .type } ?? false
            if item.kind == .field, ofType, !item.holdsNothing, let thing = graph.thing(of: ItemID(index)) {
                fields[thing, default: []].append(ItemID(index))
            }
        }
        var outside: [ItemID: [Use]] = [:]
        var working: Set<ThingID> = []
        var inheritance = Inheritance(model: model)
        for usage in graph.uses {
            guard model.item(usage.item).kind == .field, let owner = graph.thing(of: usage.item) else { continue }
            let tangle = graph.tangle(of: owner)
            let insider = usage.user.map { user in
                user == owner || (tangle != nil && graph.tangle(of: user) == tangle)
                    || inheritance.inherits(graph.thing(user).item, from: graph.thing(owner).item)
            } ?? false
            if !insider {
                outside[usage.item, default: []].append(usage)
            } else if usage.user == owner && works(model, usage) {
                working.insert(owner)
            }
        }
        var diagnostics: [Diagnostic] = []
        for (thing, fields) in fields.sorted(by: { $0.key < $1.key }) {
            let kept = fields.contains { outside[$0] == nil }
            guard kept, working.contains(thing) else { continue }
            for field in fields {
                let uses = (outside[field] ?? []).filter { !$0.copies }
                if uses.isEmpty { continue }
                let home = graph.thing(thing).home
                let concerned = context.hierarchy.isWithin(home, context.scope)
                    || uses.contains { context.hierarchy.isWithin(model.references[$0.reference].from, context.scope) }
                if concerned {
                    let others = others(context, field: field, fields: fields, outside: outside)
                    diagnostics.append(diagnostic(context, thing: thing, field: field, uses: uses, others: others))
                }
            }
        }
        return diagnostics
    }

    /// Whether `usage` is by a method that takes `self`: one that works on its type's fields.
    private func works(_ model: Model, _ usage: Use) -> Bool {
        guard let holder = model.references[usage.reference].holder else { return false }
        let item = model.item(holder)
        return item.kind == .function && item.takesSelf
    }

    /// What a picture of a leak of `field` says of the other `fields` of its
    /// type: those that are known outside too, and those it keeps.
    private func others(_ context: LintContext, field: ItemID, fields: [ItemID], outside: [ItemID: [Use]]) -> [String] {
        var known: [String] = []
        var kept: [String] = []
        for other in fields where other != field {
            switch outside[other] {
            case nil:
                kept.append(bareName(context, other))
            case let uses? where uses.contains(where: { !$0.copies }):
                known.append(bareName(context, other))
            case .some:
                break
            }
        }
        var others: [String] = []
        if !known.isEmpty { others.append("also known outside: \(Text.listed(known))") }
        if !kept.isEmpty { others.append("kept: \(Text.listed(kept))") }
        return others
    }

    /// `items` for `RunQueue::items`.
    private func bareName(_ context: LintContext, _ field: ItemID) -> String {
        let name = context.model.item(field).name
        guard let range = name.ranges(of: context.model.language.pathSeparator).last else { return name }
        return String(name[range.upperBound...])
    }

    private func diagnostic(_ context: LintContext, thing: ThingID, field: ItemID, uses: [Use], others: [String]) -> Diagnostic {
        let model = context.model
        var sites: [Location: String] = [:]
        var places: [NodeID: Set<Location>] = [:]
        for usage in uses {
            let reference = model.references[usage.reference]
            let user: String
            if let holder = reference.holder {
                user = context.hierarchy.display(model.item(holder).owner) + context.model.language.pathSeparator + Text.name(holder, in: context.model)
            } else {
                user = context.hierarchy.display(reference.from)
            }
            let through = usage.through.map { ", through `\(Text.name($0, in: context.model))`" } ?? ""
            let at = Text.site(reference, in: context.model)
            places[reference.from, default: []].insert(at)
            if sites[at] == nil {
                sites[at] = "`\(user)`\(through)"
            }
        }
        let owner = context.graph.thing(thing)
        let typeName = Text.name(owner.item, in: context.model)
        let fieldName = model.item(field).name
        let ordered = sites.sorted { $0.key < $1.key }
        var notes = ordered.prefix(Text.heldInMind).map { "\(Text.clickable($0.key)): \($0.value)" }
        if ordered.count > Text.heldInMind {
            notes.append("and \(Text.counted(ordered.count - Text.heldInMind, "more place"))")
        }
        var modules = places.map { Picture.Spread(places: $0.value.count, module: context.hierarchy.display($0.key)) }
        modules.sort { a, b in
            a.places != b.places ? a.places > b.places : Text.precedes(a.module, b.module)
        }
        let moduleCount = modules.count
        if moduleCount > Text.heldInMind {
            let more = modules[Text.heldInMind...]
            let count = more.reduce(0) { $0 + $1.places }
            modules = Array(modules[..<Text.heldInMind])
            modules.append(Picture.Spread(places: count, module: "in \(Text.counted(more.count, "more module"))"))
        }
        let home = context.hierarchy.display(owner.home)
        return Diagnostic(
            lint: .fieldLeak,
            key: home + context.model.language.pathSeparator + fieldName,
            message: "`\(fieldName)` is known outside `\(typeName)`: \(Text.counted(ordered.count, "place")) in \(Text.counted(moduleCount, "module"))",
            location: ordered.first?.key,
            notes: notes,
            picture: .spread(
                owner: home + context.model.language.pathSeparator + typeName,
                field: bareName(context, field),
                modules: modules,
                others: others
            )
        )
    }
}
