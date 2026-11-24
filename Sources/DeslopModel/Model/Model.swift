/// The plain, language-neutral model the lints read: the hierarchy, the
/// workspace's files, the items they define, every reference from code to an
/// item, and the functions that only wrap others.
public struct Model: Sendable {
    public var language: Language
    public var tree: Tree
    public var files: [SourceFile]
    public var items: [Item]
    public var references: [Reference]
    /// What each wrapper hands on. No chain of forwarders loops.
    public var wrappers: [ItemID: Wrapper]

    public init(
        language: Language,
        tree: Tree = Tree(),
        files: [SourceFile] = [],
        items: [Item] = [],
        references: [Reference] = [],
        wrappers: [ItemID: Wrapper] = [:]
    ) {
        self.language = language
        self.tree = tree
        self.files = files
        self.items = items
        self.references = references
        self.wrappers = wrappers
    }

    public func item(_ id: ItemID) -> Item {
        items[id.index]
    }

    public func file(_ id: FileID) -> SourceFile {
        files[id.index]
    }
}
