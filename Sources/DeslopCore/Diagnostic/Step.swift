/// A member of a circle, and its tie to the next one.
public struct Step: Hashable, Sendable {
    public var member: String
    /// Where the tie is first written.
    public var site: Location
    /// What of the next member the code there uses: `listen uses Stream`.
    public var uses: String

    public init(member: String, site: Location, uses: String) {
        self.member = member
        self.site = site
        self.uses = uses
    }
}
