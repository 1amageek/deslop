/// A node of the hierarchy, by its place in the tree. A node's parent has a
/// smaller identifier, so identifiers order nodes parent first.
public struct NodeID: Hashable, Comparable, Sendable, Codable {
    public let index: Int

    public init(_ index: Int) {
        self.index = index
    }

    public static func < (lhs: NodeID, rhs: NodeID) -> Bool {
        lhs.index < rhs.index
    }

    public init(from decoder: any Decoder) throws {
        index = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(index)
    }
}
