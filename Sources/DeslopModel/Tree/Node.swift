/// A level of the hierarchy.
public struct Node: Hashable, Sendable, Codable {
    public var name: String
    public var kind: NodeKind
    public var parent: NodeID?
    /// Test code, and so is everything inside it.
    public var test: Bool

    public init(name: String, kind: NodeKind, parent: NodeID?, test: Bool) {
        self.name = name
        self.kind = kind
        self.parent = parent
        self.test = test
    }
}
