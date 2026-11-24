/// One lint: what it reports of a model.
public protocol LintRule: Sendable {
    func check(_ context: LintContext) -> [Diagnostic]
}
