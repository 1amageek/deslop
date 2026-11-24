import DeslopModel

/// The ties between members of one circle-finding, by user and used.
struct Ties<Member: Hashable & Comparable & Sendable>: Sendable {
    private(set) var byKey: [TieKey<Member>: Tie] = [:]

    mutating func add(_ context: LintContext, user: Member, used: Member, item: ItemID, reference: Reference, module: NodeID) {
        let key = TieKey(user: user, used: used)
        if var tie = byKey[key] {
            tie.add(context, item: item, reference: reference, module: module)
            byKey[key] = tie
        } else {
            byKey[key] = Tie(context, item: item, reference: reference, module: module)
        }
    }

    /// Every tie, by key order.
    var sorted: [(key: TieKey<Member>, tie: Tie)] {
        byKey.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
