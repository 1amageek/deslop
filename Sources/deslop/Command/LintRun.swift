import DeslopCore
import DeslopModel
import Foundation

/// Lints a model and reports as the command line asked.
struct LintRun {
    static let tool = "deslop"

    /// What the run printed, and whether it found nothing new.
    struct Outcome {
        var standardOutput = ""
        var standardError = ""
        var clean: Bool
    }

    let reporting: Invocation.Reporting
    let colored: Bool

    func run(_ model: Model) throws(CommandError) -> Outcome {
        let scope: NodeID?
        if let query = reporting.scope {
            guard let found = Linter.resolve(model, query: query) else {
                throw .failure("\(query): no such package or module")
            }
            scope = found
        } else {
            scope = nil
        }
        let linter = Linter()
        let all = linter.check(model, scope: scope)
        if let path = reporting.updateAllow {
            let text = AllowList(diagnostics: all).text(tool: LintRun.tool)
            try write(text, to: path)
            return Outcome(standardError: "\(LintRun.tool): wrote \(all.count) entries to \(path)\n", clean: true)
        }
        var reported = all
        var fixed = 0
        if let path = reporting.allow {
            let text = try read(path)
            let allow: AllowList
            do {
                allow = try AllowList(parsing: text)
            } catch {
                throw .failure("\(path):\(error)")
            }
            // An entry is fixed only where nothing reports it, in scope or out of it.
            fixed = allow.fixedCount(scope == nil ? all : linter.check(model))
            reported = all.filter { !allow.allows($0) }
        }
        let text = Renderer(tool: LintRun.tool, colored: colored)
            .render(reported, fixedAllowed: fixed, allowPath: reporting.allow)
        return Outcome(standardOutput: text, clean: reported.isEmpty)
    }

    private func read(_ path: String) throws(CommandError) -> String {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw .failure("\(path): \(LintRun.reason(error))")
        }
    }

    /// Why a file operation failed, without the file's name, which the
    /// message already leads with.
    static func reason(_ error: any Error) -> String {
        let described = error as NSError
        return described.localizedFailureReason ?? described.localizedDescription
    }

    private func write(_ text: String, to path: String) throws(CommandError) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        } catch {
            throw .failure("\(path): \(LintRun.reason(error))")
        }
    }
}
