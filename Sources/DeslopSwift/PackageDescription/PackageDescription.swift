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

        /// The target as the layout reads it: a test or plugin target's
        /// sources count for layout only.
        var layoutTarget: LayoutTarget {
            let base = path.isEmpty || path == "." ? "" : path + "/"
            return LayoutTarget(
                name: name,
                isTest: isTest,
                root: path,
                sources: swiftSources.map { base + $0 },
                indexed: !isTest && type != "plugin"
            )
        }

        /// Its Swift sources, relative to its path, in byte order.
        var swiftSources: [String] {
            (sources ?? []).filter { $0.hasSuffix(".swift") }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        }
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

    /// Its Swift targets, as the layout reads them.
    var layoutTargets: [LayoutTarget] {
        targets.filter(\.isSwift).map(\.layoutTarget)
    }

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
