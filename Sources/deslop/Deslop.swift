import DeslopModel
import DeslopSwift
import Foundation

/// `deslop`: an architectural linter for deep modules and narrow
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
        case .lintPackage(let source, let reporting):
            let model = try sourceModel(source)
            return try report(LintRun(reporting: reporting, colored: colored()).run(model))
        case .exportModel(let source, let output):
            let model = try sourceModel(source)
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
                    throw .failure("\(output): \(LintRun.reason(error))")
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
                throw .failure("\(modelPath): \(LintRun.reason(error))")
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

    /// The model of what `source` describes: a SwiftPM package when its
    /// directory has a `Package.swift` and no Xcode option names a project;
    /// else an Xcode workspace or project there.
    private static func sourceModel(_ source: Invocation.Source) throws(CommandError) -> Model {
        let root = URL(fileURLWithPath: source.path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        let isPackage = FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path)
        do {
            if isPackage && !source.namesXcode {
                guard source.schemes.isEmpty, source.destination == nil, source.toolchain == nil else {
                    throw CommandError.usage("Xcode options apply to an Xcode project; this is a Swift package")
                }
                return try PackageFrontend(packageRoot: root, buildsIndex: source.buildsIndex).model()
            }
            return try XcodeFrontend(
                root: root,
                project: source.project,
                workspace: source.workspace,
                schemes: source.schemes,
                destination: source.destination,
                toolchain: source.toolchain,
                buildsIndex: source.buildsIndex
            ).model()
        } catch let error as CommandError {
            throw error
        } catch let error as FrontendError {
            throw .failure(error.description)
        } catch {
            throw .failure(String(describing: error))
        }
    }

    private static func report(_ outcome: LintRun.Outcome) -> Bool {
        FileHandle.standardOutput.write(Data(outcome.standardOutput.utf8))
        FileHandle.standardError.write(Data(outcome.standardError.utf8))
        return outcome.clean
    }

    /// `DESLOP_COLOR=always|never` decides, then `NO_COLOR`, then
    /// whether standard output is a terminal.
    private static func colored() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        switch environment["DESLOP_COLOR"] {
        case "always": return true
        case "never": return false
        default: return (environment["NO_COLOR"] ?? "").isEmpty && isatty(STDOUT_FILENO) != 0
        }
    }
}
