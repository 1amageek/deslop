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

    /// What to build and read: a SwiftPM package, or an Xcode project or workspace.
    struct Source: Equatable {
        /// The directory it is in.
        var path: String = "."
        var buildsIndex: Bool = true
        var project: String?
        var workspace: String?
        var schemes: [String] = []
        var destination: String?
        var toolchain: String?

        /// Whether an Xcode option names what to build.
        var namesXcode: Bool { project != nil || workspace != nil }
    }

    /// Lint the Swift package or Xcode project `source` describes.
    case lintPackage(source: Source, reporting: Reporting)
    /// Write the model of the Swift package or Xcode project `source` describes.
    case exportModel(source: Source, output: String?)
    /// Lint a model file, written by any language's frontend.
    case checkModel(modelPath: String, reporting: Reporting)
    case help
}
