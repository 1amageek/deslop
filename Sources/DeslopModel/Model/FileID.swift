/// A file of the model, by its place in the model's files.
public struct FileID: Hashable, Comparable, Sendable, Codable {
    public let index: Int

    public init(_ index: Int) {
        self.index = index
    }

    public static func < (lhs: FileID, rhs: FileID) -> Bool {
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
