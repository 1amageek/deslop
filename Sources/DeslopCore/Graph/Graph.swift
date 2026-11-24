import DeslopModel

/// Who knows what. A thing is a type with everything written for it (its
/// fields, variants, associated items and methods, wherever they are
/// written), a free function, or a free constant. A use is a reference from
/// non-test code to an item of a non-test thing, seen through wrappers: a use
/// of a forwarder is a use of the function at the end of its chain and a read
/// of the fields of `self` the chain calls on, a use of an accessor is a use
/// of its fields, and what a wrapper's own item names is no one's use. A
/// thing knows another if its code uses one of the other's items; things
/// that know each other in a circle are a tangle.
public struct Graph: Sendable {
    private let things: [Thing]
    /// By item: the thing each item is part of.
    private let thingOf: [ThingID?]
    /// The uses of non-test code, in the order of the model's references.
    public let uses: [Use]
    /// Each set of two or more things that know each other in a circle, sorted.
    private let tangles: [[ThingID]]
    /// By thing: the tangle each thing is in.
    private let tangleOf: [TangleID?]

    public init(model: Model) {
        let (things, thingOf) = Graph.things(model)
        let uses = Graph.uses(model, thingOf: thingOf)
        var knows = [[Int]](repeating: [], count: things.count)
        for usage in uses {
            if let user = usage.user, let used = thingOf[usage.item.index], user != used {
                knows[user.index].append(used.index)
            }
        }
        let tangles = StronglyConnectedComponents.circles(knows).map { $0.map(ThingID.init) }
        var tangleOf = [TangleID?](repeating: nil, count: things.count)
        for (index, members) in tangles.enumerated() {
            for member in members {
                tangleOf[member.index] = TangleID(index)
            }
        }
        self.things = things
        self.thingOf = thingOf
        self.uses = uses
        self.tangles = tangles
        self.tangleOf = tangleOf
    }

    public func thing(_ id: ThingID) -> Thing {
        things[id.index]
    }

    /// The thing `item` is part of, if it is part of one.
    public func thing(of item: ItemID) -> ThingID? {
        thingOf[item.index]
    }

    /// The tangle `thing` is in, if it is in one.
    public func tangle(of thing: ThingID) -> TangleID? {
        tangleOf[thing.index]
    }

    /// Every tangle, in order of its first member.
    public var tangleIDs: [TangleID] {
        tangles.indices.map(TangleID.init)
    }

    /// The things of `tangle`, sorted.
    public func members(of tangle: TangleID) -> [ThingID] {
        tangles[tangle.index]
    }

    /// Each thing, and the thing each item is part of: the item at the top of
    /// its chain of parents, if that is a non-test type, function or constant.
    private static func things(_ model: Model) -> ([Thing], [ThingID?]) {
        let hierarchy = Hierarchy(model: model)
        func counted(_ id: ItemID) -> Bool {
            let item = model.item(id)
            let inTestFile = item.file.map { model.file($0).test } ?? false
            return item.kind != .module && !hierarchy.isTest(item.owner) && !inTestFile
        }
        var things: [Thing] = []
        var ofRoot = [ThingID?](repeating: nil, count: model.items.count)
        var thingOf = [ThingID?](repeating: nil, count: model.items.count)
        for index in model.items.indices {
            let id = ItemID(index)
            var root = id
            while let parent = model.item(root).parent {
                root = parent
            }
            let rootItem = model.item(root)
            let isThing = rootItem.kind == .type || rootItem.kind == .function || rootItem.kind == .constant
            guard isThing, counted(id), counted(root) else { continue }
            let thing: ThingID
            if let known = ofRoot[root.index] {
                thing = known
            } else {
                things.append(Thing(item: root, home: rootItem.owner))
                thing = ThingID(things.count - 1)
                ofRoot[root.index] = thing
            }
            thingOf[index] = thing
        }
        return (things, thingOf)
    }

    /// The uses of non-test code, seen through wrappers.
    private static func uses(_ model: Model, thingOf: [ThingID?]) -> [Use] {
        func isWrapper(_ id: ItemID) -> Bool { model.wrappers[id] != nil }
        var uses: [Use] = []
        for (index, reference) in model.references.enumerated() {
            if reference.test { continue }
            if let holder = reference.holder, isWrapper(holder) { continue }
            let user = reference.holder.flatMap { thingOf[$0.index] }
            let through = isWrapper(reference.item) ? reference.item : nil
            for (item, copies) in behind(model, reference) where thingOf[item.index] != nil {
                uses.append(Use(reference: index, user: user, item: item, through: through, copies: copies))
            }
        }
        return uses
    }

    /// What `reference` uses, and whether it only reads each: the item it
    /// names, or what is behind that if it is a wrapper. A forwarder only
    /// reads the fields it calls on: its callers call the function behind it
    /// and never see them. What an accessor lends is only read where the code
    /// that calls it only reads it.
    private static func behind(_ model: Model, _ reference: Reference) -> [(ItemID, Bool)] {
        var used: [(ItemID, Bool)] = []
        var at = reference.item
        while true {
            switch model.wrappers[at] {
            case .forwarder(let target, let fields):
                used.append(contentsOf: fields.map { ($0, true) })
                at = target
            case .accessor(let lent, let copied, _):
                used.append(contentsOf: lent.map { ($0, reference.copies) })
                used.append(contentsOf: copied.map { ($0, true) })
                return used
            case nil:
                let direct = at == reference.item
                used.append((at, direct && reference.copies))
                return used
            }
        }
    }
}
