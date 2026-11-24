import Foundation

/// A SwiftPM package, as `swift package describe --type json` describes it.
struct PackageDescription: Sendable, Decodable {
    struct Target: Sendable, Decodable {
        let name: String
        /// `library`, `executable`, `test`, `macro`, `plugin`, ...
        let type: String
        /// `SwiftTarget`, `ClangTarget`, ...
        let moduleType: String?
        /// Relative to the package's root.
        let path: String
        /// Relative to the target's path.
        let sources: [String]?

        var isTest: Bool { type == "test" }
        var isSwift: Bool { moduleType == "SwiftTarget" }

        enum CodingKeys: String, CodingKey {
            case name, type, path, sources
            case moduleType = "module_type"
        }
    }

    let name: String
    /// The package's root, absolute.
    let path: String
    let targets: [Target]

    /// The package whose root is `directory`.
    static func describe(_ directory: URL, runner: CommandRunner) throws(FrontendError) -> PackageDescription {
        let data = try runner.run(["swift", "package", "--package-path", directory.path, "describe", "--type", "json"])
        do {
            return try JSONDecoder().decode(PackageDescription.self, from: data)
        } catch {
            throw .packageDescriptionUnreadable(String(describing: error))
        }
    }
}
