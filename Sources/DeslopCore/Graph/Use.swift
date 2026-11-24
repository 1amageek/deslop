import DeslopModel

/// A reference from non-test code, seen through wrappers.
public struct Use: Hashable, Sendable {
    /// The reference, by its place in the model's.
    public let reference: Int
    /// The thing whose code holds the reference.
    public let user: ThingID?
    /// What is used, past wrappers.
    public let item: ItemID
    /// The wrapper the reference names, if it names one.
    public let through: ItemID?
    /// For a field: the user only reads its value, directly or through
    /// wrappers that hand out nothing else.
    public let copies: Bool
}
