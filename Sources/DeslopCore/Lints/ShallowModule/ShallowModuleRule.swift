import DeslopModel

/// `shallow-module`: a package, or a module with child modules, that shows
/// more functions than a reader holds in mind, at least as many as it hides,
/// and a list that long: more things, or more functions of one thing. A
/// reader learns an interface one list at a time, the things it shows and
/// then the functions of one thing, so a few small types pass where one wide
/// type does not. A thing's functions are its methods and the module's free
/// functions that use it; one that uses none of the module's types is a
/// thing of its own. It counts its working functions: those that are not
/// wrappers and do not implement an interface, each at its thing's home, so
/// a method at its type's. It shows those that code outside it uses, through
/// wrappers; code is outside by its function's home, or by its module where
/// no function holds it. It shows a thing when it shows one of its functions.
public struct ShallowModuleRule: LintRule {
    /// What a module hides for each function it shows, at break-even. A
    /// module's interface is the cost of using it and what it hides is the
    /// benefit; *A Philosophy of Software Design* calls a module shallow when
    /// "the benefit of not having to learn about how they work internally is
    /// negated by the cost of learning and using their interfaces".
    static let breakEven = 1

    public init() {}

    public func check(_ context: LintContext) -> [Diagnostic] {
        let model = context.model
        let graph = context.graph
        let tree = model.tree
        let hierarchy = context.hierarchy
        let judged = judged(tree, hierarchy)
        func home(_ item: ItemID) -> NodeID? {
            graph.thing(of: item).map { graph.thing($0).home }
        }
        func working(_ item: ItemID) -> Bool {
            let function = model.item(item)
            return function.kind == .function && !function.implementsInterface && model.wrappers[item] == nil
        }
        var total: [NodeID: Int] = [:]
        for index in model.items.indices {
            let item = ItemID(index)
            guard working(item), let at = home(item) else { continue }
            for module in modulesAround(tree, hierarchy, at) where judged.contains(module) {
                total[module, default: 0] += 1
            }
        }
        var shown: [NodeID: Set<ItemID>] = [:]
        for usage in graph.uses {
            guard working(usage.item), let at = home(usage.item) else { continue }
            let reference = model.references[usage.reference]
            let user = usage.user.map { graph.thing($0).home } ?? reference.from
            for module in modulesAround(tree, hierarchy, at) {
                if within(hierarchy, user, module) { break }
                if judged.contains(module) {
                    shown[module, default: []].insert(usage.item)
                }
            }
        }
        let known = typesKnown(context)
        var diagnostics: [Diagnostic] = []
        for module in judged.sorted() {
            let total = total[module] ?? 0
            guard let shown = shown[module] else { continue }
            let hidden = max(total - shown.count, 0)
            let (notes, long) = tooLong(lists(context, known: known, module: module, shown: shown))
            let shallow = shown.count > Text.heldInMind && !notes.isEmpty && hidden <= shown.count * Self.breakEven
            if shallow && context.hierarchy.isWithin(module, context.scope) {
                let name = context.hierarchy.display(module)
                diagnostics.append(Diagnostic(
                    lint: .shallowModule,
                    key: name,
                    message: "`\(name)` is shallow: it shows \(shown.count) of its \(Text.counted(total, "function"))",
                    location: Text.moduleLocation(module, in: context.model),
                    notes: notes,
                    picture: .lists(shown: shown.count, hidden: hidden, lists: long)
                ))
            }
        }
        return diagnostics
    }

    /// The types each free function knows: those whose items its code uses.
    private func typesKnown(_ context: LintContext) -> [ThingID: Set<ThingID>] {
        let model = context.model
        let graph = context.graph
        func kind(_ thing: ThingID) -> ItemKind { model.item(graph.thing(thing).item).kind }
        var known: [ThingID: Set<ThingID>] = [:]
        for usage in graph.uses {
            if let user = usage.user, let used = graph.thing(of: usage.item),
               kind(user) == .function, kind(used) == .type {
                known[user, default: []].insert(used)
            }
        }
        return known
    }

    /// The lists a reader learns what `module` shows by, one at a time: each
    /// thing it shows, by name, with the names of its functions there, widest
    /// first. A method is on its type's list, and a free function on the list
    /// of each type of `module` it knows, or on its own if it knows none.
    private func lists(
        _ context: LintContext,
        known: [ThingID: Set<ThingID>],
        module: NodeID,
        shown: Set<ItemID>
    ) -> [(name: String, functions: [String])] {
        let graph = context.graph
        var lists: [ThingID: [String]] = [:]
        for function in shown.sorted() {
            guard let thing = graph.thing(of: function) else { continue }
            var on = [thing]
            if graph.thing(thing).item == function {
                let types = (known[thing] ?? []).sorted().filter { within(context.hierarchy, graph.thing($0).home, module) }
                if !types.isEmpty { on = types }
            }
            for list in on {
                lists[list, default: []].append(Text.name(function, in: context.model))
            }
        }
        let named = lists.map { thing, functions in
            (name: Text.name(graph.thing(thing).item, in: context.model), functions: Text.sorted(functions))
        }
        let byName = named.sorted { a, b in
            if a.name != b.name { return Text.precedes(a.name, b.name) }
            return a.functions.lexicographicallyPrecedes(b.functions, by: Text.precedes)
        }
        // A stable sort by width, widest first, keeps names in order within a width.
        return byName.enumerated().sorted { a, b in
            a.element.functions.count != b.element.functions.count
                ? a.element.functions.count > b.element.functions.count
                : a.offset < b.offset
        }.map(\.element)
    }

    /// A note for each of `lists` longer than a reader holds in mind, the list
    /// of things first, then each thing's functions; and each such list's
    /// name and length, `things` for the list of things.
    private func tooLong(_ lists: [(name: String, functions: [String])]) -> ([String], [Picture.Bar]) {
        var notes: [String] = []
        var long: [Picture.Bar] = []
        if lists.count > Text.heldInMind {
            notes.append("shows \(Text.counted(lists.count, "thing")): \(Text.listed(lists.map(\.name)))")
            long.append(Picture.Bar(name: "things", length: lists.count))
        }
        for list in lists where list.functions.count > Text.heldInMind {
            notes.append("`\(list.name)` shows \(Text.counted(list.functions.count, "function")): \(Text.listed(list.functions))")
            long.append(Picture.Bar(name: list.name, length: list.functions.count))
        }
        return (notes, long)
    }

    /// Every package, and every non-test module with child modules.
    private func judged(_ tree: Tree, _ hierarchy: Hierarchy) -> Set<NodeID> {
        var parents: Set<NodeID> = []
        for id in tree.ids where !hierarchy.isTest(id) {
            if let parent = tree.parent(id) { parents.insert(parent) }
        }
        return Set(tree.ids.filter { id in
            guard !hierarchy.isTest(id) else { return false }
            switch tree.node(id).kind {
            case .package: return true
            case .module: return parents.contains(id)
            case .workspace: return false
            }
        })
    }

    /// `node`, then the modules around it, up to its package.
    private func modulesAround(_ tree: Tree, _ hierarchy: Hierarchy, _ node: NodeID) -> [NodeID] {
        let package = hierarchy.packageOf(node)
        var around: [NodeID] = []
        for ancestor in hierarchy.ancestors(node) {
            guard hierarchy.packageOf(ancestor) == package, tree.node(ancestor).kind != .workspace else { break }
            around.append(ancestor)
        }
        return around
    }

    /// Whether `node` is in `module`'s subtree, its package's code and not another package's.
    private func within(_ hierarchy: Hierarchy, _ node: NodeID, _ module: NodeID) -> Bool {
        hierarchy.isWithin(node, module) && hierarchy.packageOf(node) == hierarchy.packageOf(module)
    }
}
