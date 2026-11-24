import Foundation

/// What a unit of the index says of itself: one compilation of one file.
struct IndexUnit: Sendable {
    /// When the unit was written.
    struct Time: Comparable, Sendable {
        let seconds: Int64
        let nanoseconds: Int64

        static func < (lhs: Time, rhs: Time) -> Bool {
            lhs.seconds != rhs.seconds ? lhs.seconds < rhs.seconds : lhs.nanoseconds < rhs.nanoseconds
        }

        /// Whether a file modified at `date` changed after this time.
        func precedes(_ date: Date) -> Bool {
            let since1970 = date.timeIntervalSince1970
            let seconds = Int64(since1970.rounded(.down))
            let nanoseconds = Int64(((since1970 - Double(seconds)) * 1_000_000_000).rounded(.down))
            return self < Time(seconds: seconds, nanoseconds: nanoseconds)
        }
    }

    /// A record the unit depends on: the occurrences of one file, or of a
    /// system module's interface.
    struct Record: Sendable {
        let path: String
        let name: String
        let isSystem: Bool
    }

    let isSystem: Bool
    /// The file it compiled, if it compiled one.
    let mainFile: String?
    let modified: Time
    let records: [Record]
}
