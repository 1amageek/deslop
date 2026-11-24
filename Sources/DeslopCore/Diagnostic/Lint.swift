/// The lints, in the order their reports come.
public enum Lint: Int, CaseIterable, Comparable, Sendable {
    case moduleCycle
    case tangle
    case fieldLeak
    case shallowModule
    case wideDirectory
    case longFile

    /// The name reports and allowlists write.
    public var name: String {
        switch self {
        case .moduleCycle: "module-cycle"
        case .tangle: "tangle"
        case .fieldLeak: "field-leak"
        case .shallowModule: "shallow-module"
        case .wideDirectory: "wide-directory"
        case .longFile: "long-file"
        }
    }

    public init?(name: String) {
        guard let lint = Lint.allCases.first(where: { $0.name == name }) else { return nil }
        self = lint
    }

    public static func < (lhs: Lint, rhs: Lint) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
