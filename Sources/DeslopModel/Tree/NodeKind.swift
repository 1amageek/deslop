/// What a level of the hierarchy is.
public enum NodeKind: String, Hashable, Sendable, Codable {
    /// The root: everything the model describes.
    case workspace
    /// A unit the language's build keeps in order: a Rust crate, a Swift target.
    case package
    /// A part of a package: a Rust module, a Swift component directory.
    case module
}
