import DeslopModel

/// A type with everything written for it, a free function, or a free constant.
public struct Thing: Hashable, Sendable {
    /// The type, function, or constant.
    public let item: ItemID
    /// The module it is defined in, which is also its methods' home.
    public let home: NodeID
}
