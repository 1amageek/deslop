/// A thing of the graph, by its place in the graph's things.
public struct ThingID: Hashable, Comparable, Sendable {
    public let index: Int

    public init(_ index: Int) {
        self.index = index
    }

    public static func < (lhs: ThingID, rhs: ThingID) -> Bool {
        lhs.index < rhs.index
    }
}
