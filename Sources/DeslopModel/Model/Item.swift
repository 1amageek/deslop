/// Something code defines and other code names.
public struct Item: Hashable, Sendable, Codable {
    /// How its module writes it, joined by the language's path separator:
    /// `Ready`, `Ready::new`, `RunQueue.items`.
    public var name: String
    /// The module it is written in.
    public var owner: NodeID
    /// The module it is, for a module.
    public var module: NodeID?
    public var file: FileID?
    public var kind: ItemKind
    /// What it is written for: a type, for its fields, variants, associated
    /// items and methods, wherever they are written; a variant, for its
    /// fields. `nil` for a free item.
    public var parent: ItemID?
    /// A function that implements an interface's requirement or overrides
    /// another: one of a Rust trait's `impl` block, a Swift protocol witness.
    public var implementsInterface: Bool
    /// A function that works on an instance of its type: it takes `self`.
    public var takesSelf: Bool
    /// A field of a marker type, which holds nothing.
    public var holdsNothing: Bool
    /// For a type, the types whose implementation it inherits and extends,
    /// such as a class's superclass: what it may work on as its own. An
    /// interface it only conforms to is none of them.
    public var inherits: [ItemID]

    public init(
        name: String,
        owner: NodeID,
        module: NodeID? = nil,
        file: FileID? = nil,
        kind: ItemKind,
        parent: ItemID? = nil,
        implementsInterface: Bool = false,
        takesSelf: Bool = false,
        holdsNothing: Bool = false,
        inherits: [ItemID] = []
    ) {
        self.name = name
        self.owner = owner
        self.module = module
        self.file = file
        self.kind = kind
        self.parent = parent
        self.implementsInterface = implementsInterface
        self.takesSelf = takesSelf
        self.holdsNothing = holdsNothing
        self.inherits = inherits
    }
}
