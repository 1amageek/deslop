/// A source file of the workspace.
public struct SourceFile: Hashable, Sendable, Codable {
    /// Relative to the workspace's root, `/`-separated.
    public var path: String
    /// The module it is part of.
    public var module: NodeID
    public var test: Bool
    /// Every line of its text, blank and comment lines too.
    public var lines: Int
    /// Where a reader starts reading its module: 0 for the module's root file,
    /// 1 for a file that declares a directory, 2 for any other, 3 for an example.
    public var rank: Int
    /// The directory, relative and `/`-separated, whose members this file
    /// declares, if it declares one.
    public var declares: String?

    public init(
        path: String,
        module: NodeID,
        test: Bool,
        lines: Int,
        rank: Int = 2,
        declares: String? = nil
    ) {
        self.path = path
        self.module = module
        self.test = test
        self.lines = lines
        self.rank = rank
        self.declares = declares
    }
}
