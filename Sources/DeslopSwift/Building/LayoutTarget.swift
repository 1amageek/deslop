/// A unit of a build as the layout reads it: a SwiftPM target, an Xcode
/// target, a module of a local package.
struct LayoutTarget: Sendable {
    let name: String
    let isTest: Bool
    /// Relative to the root of what is built, `/`-separated; empty for that
    /// root itself. Its directories are the target's modules.
    let root: String
    /// Relative to the root of what is built, `/`-separated.
    let sources: [String]
    /// Whether the build compiles its sources into a module the lints read.
    let indexed: Bool
}
