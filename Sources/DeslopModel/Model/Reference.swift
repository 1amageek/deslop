/// A place where code names an item.
public struct Reference: Hashable, Sendable, Codable {
    public var file: FileID
    /// 1-based.
    public var line: Int
    /// The module it is written in.
    public var from: NodeID
    /// The innermost item whose definition holds it: a function, type,
    /// field, variant or constant. `nil` where no item's definition does,
    /// such as an `impl` block's or an extension's header.
    public var holder: ItemID?
    public var item: ItemID
    /// For a field: the code only reads its value; it neither writes the
    /// field nor reaches into it. For a call of an accessor that lends to
    /// read, directly or through forwarders: the code only reads what it lends.
    public var copies: Bool
    public var test: Bool

    public init(
        file: FileID,
        line: Int,
        from: NodeID,
        holder: ItemID?,
        item: ItemID,
        copies: Bool = false,
        test: Bool = false
    ) {
        self.file = file
        self.line = line
        self.from = from
        self.holder = holder
        self.item = item
        self.copies = copies
        self.test = test
    }
}
