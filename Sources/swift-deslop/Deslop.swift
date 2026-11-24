import DeslopModel
import DeslopSwift
import Foundation

/// `swift-deslop`: an architectural linter for deep modules and narrow
/// interfaces. Exits 0 when it reports nothing, 1 when it reports, 2 when it
/// cannot run.
@main
struct Deslop {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do throws(CommandError) {
            let invocation = try InvocationParser.parse(arguments)
            let clean = try run(invocation)
            exit(clean ? 0 : 1)
        } catch {
            switch error {
            case .usage(let reason):
                FileHandle.standardError.write(Data("\(LintRun.tool): \(reason)\n\n\(InvocationParser.usage)".utf8))
            case .failure(let reason):
                FileHandle.standardError.write(Data("\(LintRun.tool): \(reason)\n".utf8))
            }
            exit(2)
        }
    }

    /// Runs `invocation`; whether it found nothing new to report.
    static func run(_ invocation: Invocation) throws(CommandError) -> Bool {
        switch invocation {
        case .help:
            print(InvocationParser.usage, terminator: "")
            return true
        case .lintPackage(let packagePath, let buildsIndex, let reporting):
            let model = try packageModel(packagePath, buildsIndex: buildsIndex)
            return try report(LintRun(reporting: reporting, colored: colored()).run(model))
        case .exportModel(let packagePath, let buildsIndex, let output):
            let model = try packageModel(packagePath, buildsIndex: buildsIndex)
            let data: Data
            do {
                data = try ModelCodec.encode(model)
            } catch {
                throw .failure(error.description)
            }
            if let output {
                do {
                    try data.write(to: URL(fileURLWithPath: output))
                } catch {
                    throw .failure("\(output): \(error.localizedDescription)")
                }
            } else {
                FileHandle.standardOutput.write(data + Data("\n".utf8))
            }
            return true
        case .checkModel(let modelPath, let reporting):
            let data: Data
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: modelPath))
            } catch {
                throw .failure("\(modelPath): \(error.localizedDescription)")
            }
            let model: Model
            do {
                model = try ModelCodec.decode(data)
            } catch {
                throw .failure("\(modelPath): \(error.description)")
            }
            return try report(LintRun(reporting: reporting, colored: colored()).run(model))
        }
    }

    private static func packageModel(_ path: String, buildsIndex: Bool) throws(CommandError) -> Model {
        let root = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        do {
            return try SwiftPackageFrontend(packageRoot: root, buildsIndex: buildsIndex).model()
        } catch {
            throw .failure(error.description)
        }
    }

    private static func report(_ outcome: LintRun.Outcome) -> Bool {
        FileHandle.standardOutput.write(Data(outcome.standardOutput.utf8))
        FileHandle.standardError.write(Data(outcome.standardError.utf8))
        return outcome.clean
    }

    /// `SWIFT_DESLOP_COLOR=always|never` decides, then `NO_COLOR`, then
    /// whether standard output is a terminal.
    private static func colored() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        switch environment["SWIFT_DESLOP_COLOR"] {
        case "always": return true
        case "never": return false
        default: return (environment["NO_COLOR"] ?? "").isEmpty && isatty(STDOUT_FILENO) != 0
        }
    }
}
