import DeslopModel

/// Runs every lint over a model.
public struct Linter: Sendable {
    private let rules: [any LintRule]

    public init(rules: [any LintRule] = Linter.standardRules) {
        self.rules = rules
    }

    public static let standardRules: [any LintRule] = [
        ModuleCycleRule(),
        TangleRule(),
        FieldLeakRule(),
        ShallowModuleRule(),
        LayoutRule(),
    ]

    /// Every report, optionally only where `scope`, a package or module, is
    /// concerned, by lint and then by key.
    public func check(_ model: Model, scope: NodeID? = nil) -> [Diagnostic] {
        let context = LintContext(model: model, scope: scope)
        return rules.flatMap { $0.check(context) }.sorted { a, b in
            a.lint != b.lint ? a.lint < b.lint : Text.precedes(a.key, b.key)
        }
    }

    /// The package or module `query` names, as reports write it. A package
    /// name written with `-` also matches its `_` form.
    public static func resolve(_ model: Model, query: String) -> NodeID? {
        let normalized = String(query.map { $0 == "-" ? "_" : $0 })
        let hierarchy = Hierarchy(model: model)
        return model.tree.ids.first { id in
            guard model.tree.node(id).kind != .workspace else { return false }
            let shown = hierarchy.display(id)
            return shown == query || shown == normalized
        }
    }
}
