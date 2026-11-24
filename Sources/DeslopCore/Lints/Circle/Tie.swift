import DeslopModel

/// The references by which one member of a circle knows another.
struct Tie: Sendable {
    /// The first of `sites`.
    private(set) var site: Location
    private(set) var items: Set<ItemID> = []
    /// The items whose code holds them.
    private(set) var holders: Set<ItemID> = []
    private(set) var sites: Set<Location> = []
    /// By each module it is written in, as its report counts them, its first site there.
    private(set) var written: [NodeID: Location] = [:]

    /// A tie of one reference, which is to `item` or to a wrapper of it, written in `module`.
    init(_ context: LintContext, item: ItemID, reference: Reference, module: NodeID) {
        site = Text.site(reference, in: context.model)
        add(context, item: item, reference: reference, module: module)
    }

    /// Adds `reference`, which is to `item` or to a wrapper of it, written in `module`.
    mutating func add(_ context: LintContext, item: ItemID, reference: Reference, module: NodeID) {
        items.insert(item)
        if let holder = reference.holder {
            holders.insert(holder)
        }
        let site = Text.site(reference, in: context.model)
        if let first = written[module] {
            if site < first { written[module] = site }
        } else {
            written[module] = site
        }
        sites.insert(site)
        if site < self.site { self.site = site }
    }

    /// How many items it ties by: what cutting it takes.
    var cost: Int { items.count }

    /// `src/kinds.rs:2:1: `kinds` uses `socket` by 1 item: LIMIT`, and the
    /// first site in each other module it is written in.
    func note(_ context: LintContext, verb: String, user: String, used: String) -> String {
        let site = self.site
        let firsts = Set(written.values).sorted()
        let elsewhere = firsts.filter { $0 != site }.map(Text.clickable)
        let also = elsewhere.isEmpty ? "" : "; also at \(Text.listed(elsewhere))"
        let names = Text.listed(Text.names(items, in: context.model))
        return "\(Text.clickable(site)): `\(user)` \(verb) `\(used)` by \(Text.counted(items.count, "item")): \(names)\(also)"
    }

    /// The step of a circle from `member`, whose code it is in: what it uses
    /// of the next, and the item whose code does, when that is one.
    func step(_ context: LintContext, member: String) -> Step {
        let used = Text.grouped(Text.names(items, in: context.model), separator: context.model.language.pathSeparator)
        let holderNames = Text.names(holders, in: context.model)
        let uses = holderNames.count == 1 ? "\(holderNames[0]) uses \(used)" : "uses \(used)"
        return Step(member: member, site: site, uses: uses)
    }
}
