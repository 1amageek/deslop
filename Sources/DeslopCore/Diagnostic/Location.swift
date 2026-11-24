/// A line of a file.
public struct Location: Hashable, Comparable, Sendable {
    public var file: String
    /// 1-based.
    public var line: Int

    public init(file: String, line: Int) {
        self.file = file
        self.line = line
    }

    /// By file, compared byte by byte as `Text.precedes` does, then by line.
    public static func < (lhs: Location, rhs: Location) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file.utf8.lexicographicallyPrecedes(rhs.file.utf8)
        }
        return lhs.line < rhs.line
    }
}
