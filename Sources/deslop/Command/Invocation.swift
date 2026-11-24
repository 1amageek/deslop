import Foundation

/// What the command line asks for.
enum Invocation: Equatable {
    /// Where the lints' reports go, and what of them an allowlist suppresses.
    struct Reporting: Equatable {
        /// A package or module: only what concerns it is reported.
        var scope: String?
        var allow: String?
        var updateAllow: String?
    }

    /// Lint the Swift package at `packagePath`.
    case lintPackage(packagePath: String, buildsIndex: Bool, reporting: Reporting)
    /// Write the model of the Swift package at `packagePath`.
    case exportModel(packagePath: String, buildsIndex: Bool, output: String?)
    /// Lint a model file, written by any language's frontend.
    case checkModel(modelPath: String, reporting: Reporting)
    case help
}
