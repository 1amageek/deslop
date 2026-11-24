/// Why an allowlist cannot be read or written.
public enum AllowListError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Line `line` (1-based) is not `<lint> <key>` with a known lint.
    case invalidEntry(line: Int)
    case unreadable(path: String, reason: String)
    case unwritable(path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidEntry(let line): "\(line): invalid allowlist entry"
        case .unreadable(let path, let reason): "\(path): \(reason)"
        case .unwritable(let path, let reason): "\(path): \(reason)"
        }
    }
}
