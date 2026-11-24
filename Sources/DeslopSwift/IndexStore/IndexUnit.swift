/// What a unit of the index says of itself: one compilation of one file.
struct IndexUnit: Sendable {
    /// When the unit was written.
    struct Time: Comparable, Sendable {
        let seconds: Int64
        let nanoseconds: Int64

        static func < (lhs: Time, rhs: Time) -> Bool {
            lhs.seconds != rhs.seconds ? lhs.seconds < rhs.seconds : lhs.nanoseconds < rhs.nanoseconds
        }
    }

    /// A record the unit depends on: the occurrences of one file.
    struct Record: Sendable {
        let path: String
        let name: String
    }

    let isSystem: Bool
    /// The file it compiled, if it compiled one.
    let mainFile: String?
    let modified: Time
    let records: [Record]
}
