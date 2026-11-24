/// A report of one lint.
public struct Diagnostic: Hashable, Sendable {
    public var lint: Lint
    /// Stable identifier used in the allowlist.
    public var key: String
    public var message: String
    public var location: Location?
    public var notes: [String]
    public var picture: Picture

    public init(lint: Lint, key: String, message: String, location: Location?, notes: [String], picture: Picture) {
        self.lint = lint
        self.key = key
        self.message = message
        self.location = location
        self.notes = notes
        self.picture = picture
    }
}
