/// A tangle of the graph, by its place in the graph's tangles.
public struct TangleID: Hashable, Comparable, Sendable {
    public let index: Int

    public init(_ index: Int) {
        self.index = index
    }

    public static func < (lhs: TangleID, rhs: TangleID) -> Bool {
        lhs.index < rhs.index
    }
}
