/// Why the command cannot run.
enum CommandError: Error, Equatable, CustomStringConvertible {
    case usage(String)
    case failure(String)

    var description: String {
        switch self {
        case .usage(let reason): reason
        case .failure(let reason): reason
        }
    }
}
