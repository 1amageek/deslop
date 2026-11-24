/// What an item is, as far as the lints tell items apart.
public enum ItemKind: String, Hashable, Sendable, Codable {
    case module
    /// A struct, class, enum, trait, protocol, union, or type alias.
    case type
    /// A block of a type's items that code names as `Self`, such as a Rust `impl` block.
    case impl
    /// A function, method, initializer, or computed property.
    case function
    /// A stored field of a type.
    case field
    /// An enum's variant.
    case variant
    /// A constant or a static.
    case constant
    case other
}
