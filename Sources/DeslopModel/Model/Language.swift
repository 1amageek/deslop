/// What the lints need to know of the language a model describes: only how
/// it writes names.
public struct Language: Hashable, Sendable, Codable {
    /// `rust`, `swift`.
    public var name: String
    /// What joins a module's or a type's name to the names inside it:
    /// `::` for Rust, `.` for Swift.
    public var pathSeparator: String

    public init(name: String, pathSeparator: String) {
        self.name = name
        self.pathSeparator = pathSeparator
    }
}
