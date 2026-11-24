import DeslopModel

/// Why the Swift frontend cannot build a model.
public enum SwiftFrontendError: Error, Equatable, Sendable, CustomStringConvertible {
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
    case sourceUnreadable(path: String, reason: String)
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
        case .sourceUnreadable(let path, let reason):
            "\(path): \(reason)"
        case .invalidModel(let error):
            "the Swift frontend built an invalid model: \(error)"
        }
    }
}
