import DeslopModel

/// What every lint reads: the model, its graph and hierarchy, and the part
/// of the model the report is about. It is a plain record; what the lints
/// ask of the model, they ask of its parts.
public struct LintContext: Sendable {
    public let model: Model
    public let graph: Graph
    public let hierarchy: Hierarchy
    /// A package or module: only what concerns it is reported. `nil` for everything.
    public let scope: NodeID?

    public init(model: Model, scope: NodeID?) {
        self.model = model
        graph = Graph(model: model)
        hierarchy = Hierarchy(model: model)
        self.scope = scope
    }
}
