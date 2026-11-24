/// A directed pair of members, the user first: the key of a tie.
struct TieKey<Member: Hashable & Comparable & Sendable>: Hashable, Comparable, Sendable {
    let user: Member
    let used: Member

    static func < (lhs: TieKey, rhs: TieKey) -> Bool {
        lhs.user != rhs.user ? lhs.user < rhs.user : lhs.used < rhs.used
    }
}
