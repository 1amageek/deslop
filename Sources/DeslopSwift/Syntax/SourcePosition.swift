/// A place in a file, as the index writes it: 1-based line, 1-based UTF-8 column.
struct SourcePosition: Hashable, Comparable, Sendable {
    let line: Int
    let column: Int

    static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        lhs.line != rhs.line ? lhs.line < rhs.line : lhs.column < rhs.column
    }
}
