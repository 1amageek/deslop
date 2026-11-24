import DeslopModel

/// Why the Swift frontend cannot build a model.
public enum FrontendError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A command could not be started, or it failed.
    case commandFailed(command: String, status: Int32, output: String)
    /// `swift package describe` printed something that is not a package description.
    case packageDescriptionUnreadable(String)
    /// libIndexStore could not be loaded, or lacks a function this reads.
    case indexStoreLibraryUnavailable(String)
    /// No index store was found where the build writes one.
    case indexStoreMissing(scratchPath: String)
    /// The index store could not be opened or read.
    case indexStoreUnreadable(String)
    /// A source file of the package has no index: it was not built.
    case sourceNotIndexed(path: String)
    /// A source file changed after the build that indexed it, so the index describes other text.
    case indexStale(path: String)
    case sourceUnreadable(path: String, reason: String)
    /// No Xcode workspace or project is at the top of `directory`.
    case noProject(directory: String)
    /// More than one workspace, or more than one project, is there.
    case ambiguousProject(directory: String, candidates: [String])
    /// A project or workspace file cannot be read.
    case projectUnreadable(path: String, reason: String)
    /// A scheme `--scheme` names is not one the container lists.
    case schemeNotFound(scheme: String, available: [String])
    /// No platform is one every target of the scheme supports.
    case noDestination(scheme: String)
    /// A non-test target with Swift sources that no built scheme compiled.
    case targetNotBuilt(target: String)
    /// The model built breaks an invariant of the model's contract: a defect of the frontend.
    case invalidModel(ModelError)

    public var description: String {
        switch self {
        case .commandFailed(let command, let status, let output):
            "`\(command)` failed with status \(status)\(output.isEmpty ? "" : ":\n\(output)")"
        case .packageDescriptionUnreadable(let reason):
            "not inside a Swift package: \(reason)"
        case .indexStoreLibraryUnavailable(let reason):
            "libIndexStore is unavailable: \(reason)"
        case .indexStoreMissing(let scratchPath):
            "no index store under \(scratchPath); build with the index store enabled"
        case .indexStoreUnreadable(let reason):
            "the index store cannot be read: \(reason)"
        case .sourceNotIndexed(let path):
            "\(path): the index holds no record of this file; build it first"
        case .indexStale(let path):
            "\(path): changed since the index was built; build again, without `--skip-build`"
        case .sourceUnreadable(let path, let reason):
            "\(path): \(reason)"
        case .noProject(let directory):
            "\(directory): not a Swift package (no Package.swift) nor an Xcode project or workspace"
        case .ambiguousProject(let directory, let candidates):
            "\(directory): holds \(candidates.joined(separator: ", ")); pass `--project` or `--workspace`"
        case .projectUnreadable(let path, let reason):
            "\(path): \(reason)"
        case .schemeNotFound(let scheme, let available):
            "no scheme `\(scheme)`; the schemes are \(available.joined(separator: ", "))"
        case .noDestination(let scheme):
            "scheme \(scheme): its targets share no platform to build for; pass `--destination`"
        case .targetNotBuilt(let target):
            "target \(target): no scheme built it, so its code is not checked; add it to a scheme, or pass `--scheme` to check only some"
        case .invalidModel(let error):
            "the Swift frontend built an invalid model: \(error)"
        }
    }
}
