import DeslopModel
import Foundation
import TestHeartbeat
import Testing

/// The `deslop` executable, run as a lint is: its exit codes, its
/// report, its allowlist, and its check of a model any frontend wrote.
@Suite("deslop command line", .heartbeat, .timeLimit(.minutes(10)))
struct CommandLineTests {
    private final class BundleMarker {}

    private struct Run {
        let status: Int32
        let output: String
        let error: String
    }

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// The executable the test bundle was built with: beside the `.xctest`
    /// bundle on macOS, in the directory Linux names as the bundle.
    private static let executable: URL = {
        let bundle = Bundle(for: BundleMarker.self).bundleURL
        let directory = bundle.pathExtension == "xctest" ? bundle.deletingLastPathComponent() : bundle
        return directory.appendingPathComponent("deslop")
    }()

    private func run(_ arguments: [String], in directory: URL) throws -> Run {
        let process = Process()
        process.executableURL = CommandLineTests.executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(["DESLOP_COLOR": "never"]) { $1 }
        let scratch = try temporaryDirectory()
        let outputFile = scratch.appendingPathComponent("stdout")
        let errorFile = scratch.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputFile)
        let errorHandle = try FileHandle(forWritingTo: errorFile)
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()
        let run = Run(
            status: process.terminationStatus,
            output: try String(contentsOf: outputFile, encoding: .utf8),
            error: try String(contentsOf: errorFile, encoding: .utf8)
        )
        try FileManager.default.removeItem(at: scratch)
        return run
    }

    /// The last line `text` prints.
    private func lastLine(_ text: String) -> Substring? {
        text.split(separator: "\n").last
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deslop-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A copy of a fixture package, and the directory holding it.
    private func fixture(_ family: String) throws -> (package: URL, scratch: URL) {
        let scratch = try temporaryDirectory()
        let package = scratch.appendingPathComponent(family)
        try FileManager.default.copyItem(at: CommandLineTests.fixtures.appendingPathComponent(family), to: package)
        return (package, scratch)
    }

    private func copyVariant(_ family: String, _ variant: String, onto package: URL) throws {
        try copyFiles(from: CommandLineTests.fixtures.appendingPathComponent("variants/\(family)/\(variant)"), onto: package)
    }

    /// Copies each file below `source` to the same place below `package`, over what is there.
    private func copyFiles(from source: URL, onto package: URL) throws {
        let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(source.path.count + 1))
            let destination = package.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }

    @Test("a clean package exits 0 and says ok")
    func clean() throws {
        let (package, scratch) = try fixture("Clean")
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let result = try run([], in: package)
        #expect(result.status == 0, "\(result.error)")
        #expect(lastLine(result.output) == "deslop: ok")
    }

    @Test("a report exits 1; the allowlist suppresses only what it lists and notes what is fixed")
    func allowlist() throws {
        let (package, scratch) = try fixture("FieldLeak")
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let reported = try run([], in: package)
        #expect(reported.status == 1, "\(reported.error)")
        #expect(lastLine(reported.output) == "deslop: 2 errors, well done!")

        let allow = scratch.appendingPathComponent("debt.allow").path
        let updated = try run(["--update-allow", allow], in: package)
        #expect(updated.status == 0)
        #expect(updated.error.hasPrefix("deslop: wrote 2 entries"))
        let entries = try String(contentsOfFile: allow, encoding: .utf8)
        #expect(entries.hasSuffix(
            "field-leak RunQueue.Queue.RunQueue.head\nfield-leak RunQueue.Queue.RunQueue.items\n"
        ))
        let allowed = try run(["--allow", allow], in: package)
        #expect(allowed.status == 0)
        #expect(lastLine(allowed.output) == "deslop: ok")

        try copyVariant("FieldLeak", "real", onto: package)
        let fixed = try run(["--allow", allow], in: package)
        #expect(fixed.status == 0)
        #expect(fixed.output.contains("2 allowed entries in \(allow) are now fixed"))

        try copyFiles(from: CommandLineTests.fixtures.appendingPathComponent("FieldLeak"), onto: package)
        try copyVariant("FieldLeak", "getters", onto: package)
        let new = try run(["--allow", allow], in: package)
        #expect(new.status == 1, "\(new.error)")
        #expect(new.output.contains("`RunQueue.storage` is known outside"))
    }

    @Test("a model any frontend writes is checked by the same lints")
    func checkModel() throws {
        let scratch = try temporaryDirectory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        // A Rust crate's model, as deslop-please's own cycle test describes it.
        var tree = Tree()
        let crate = tree.child(of: Tree.root, kind: .package, name: "p")
        let socket = tree.child(of: crate, kind: .module, name: "socket")
        let kinds = tree.child(of: crate, kind: .module, name: "kinds")
        let model = Model(
            language: Language(name: "rust", pathSeparator: "::"),
            tree: tree,
            files: [
                SourceFile(path: "src/socket.rs", module: socket, test: false, lines: 1),
                SourceFile(path: "src/kinds.rs", module: kinds, test: false, lines: 1),
            ],
            items: [
                Item(name: "open", owner: socket, file: FileID(0), kind: .function),
                Item(name: "LIMIT", owner: socket, file: FileID(0), kind: .constant),
                Item(name: "Stream", owner: kinds, file: FileID(1), kind: .type),
                Item(name: "fits", owner: kinds, file: FileID(1), kind: .function),
            ],
            references: [
                Reference(file: FileID(0), line: 1, from: socket, holder: ItemID(0), item: ItemID(2)),
                Reference(file: FileID(1), line: 2, from: kinds, holder: ItemID(3), item: ItemID(1)),
            ]
        )
        let path = scratch.appendingPathComponent("model.json")
        try ModelCodec.encode(model).write(to: path)
        let result = try run(["check", "--model", path.path], in: scratch)
        #expect(result.status == 1, "\(result.error)")
        #expect(result.output.contains("error[module-cycle]: 2 modules in `p` use each other in a circle"))
        #expect(result.output.contains("= note: src/kinds.rs:2:1: `kinds` uses `socket` by 1 item: LIMIT"))
        let scoped = try run(["check", "--model", path.path, "p::kinds"], in: scratch)
        #expect(scoped.status == 1)
        let missing = try run(["check", "--model", path.path, "p::nowhere"], in: scratch)
        #expect(missing.status == 2)
        #expect(missing.error.contains("p::nowhere: no such package or module"))
    }

    @Test("a model that breaks the contract is refused with exit 2")
    func invalidModel() throws {
        let scratch = try temporaryDirectory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let path = scratch.appendingPathComponent("model.json")
        try Data(#"{"format":"deslop-model","version":7}"#.utf8).write(to: path)
        let result = try run(["check", "--model", path.path], in: scratch)
        #expect(result.status == 2)
        #expect(result.error.contains("model.json: not a model"))
    }

    @Test("the package's model is written as JSON that `check` reads back")
    func exportModel() throws {
        let (package, scratch) = try fixture("ModuleCycle")
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let path = scratch.appendingPathComponent("net.json").path
        let exported = try run(["model", "--output", path], in: package)
        #expect(exported.status == 0, "\(exported.error)")
        let model = try ModelCodec.decode(try Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(model.language == Language(name: "swift", pathSeparator: "."))
        let checked = try run(["check", "--model", path], in: scratch)
        #expect(checked.status == 1)
        #expect(checked.output.contains("error[module-cycle]: 2 modules in `Net` use each other in a circle"))
    }

    @Test("outside a package, or with a wrong option, it cannot run: exit 2")
    func cannotRun() throws {
        let scratch = try temporaryDirectory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let outside = try run([], in: scratch)
        #expect(outside.status == 2)
        #expect(outside.error.hasPrefix("deslop: "))
        let wrong = try run(["--allow"], in: scratch)
        #expect(wrong.status == 2)
        #expect(wrong.error.contains("`--allow` needs one value"))
        let both = try run(["--allow", "a", "--update-allow", "b"], in: scratch)
        #expect(both.status == 2)
    }

    @Test("help prints for any command, its lines aligned under the command")
    func help() throws {
        let scratch = try temporaryDirectory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let plain = try run(["--help"], in: scratch)
        #expect(plain.status == 0)
        let lines = plain.output.split(separator: "\n", omittingEmptySubsequences: false)
        let first = try #require(lines.first)
        let second = lines[1]
        let firstOption = try #require(first.firstIndex(of: "["))
        let continued = try #require(second.firstIndex(of: "["))
        #expect(first.distance(from: first.startIndex, to: firstOption) == second.distance(from: second.startIndex, to: continued))
        #expect(try run(["check", "--help"], in: scratch).status == 0)
    }

    @Test("a missing allowlist is named once, and a repeated option is said to be repeated")
    func messages() throws {
        let scratch = try temporaryDirectory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let model = scratch.appendingPathComponent("model.json")
        try ModelCodec.encode(Model(language: Language(name: "swift", pathSeparator: "."))).write(to: model)
        let missing = try run(["check", "--model", model.path, "--allow", "nowhere.allow"], in: scratch)
        #expect(missing.status == 2)
        #expect(missing.error.components(separatedBy: "nowhere.allow").count == 2, "\(missing.error)")
        let repeated = try run(["check", "--model", "a.json", "--model", "b.json"], in: scratch)
        #expect(repeated.status == 2)
        #expect(repeated.error.contains("`--model` is given more than once"))
    }

    @Test("a scoped run counts as fixed only what is fixed everywhere")
    func scopedFixedCount() throws {
        let scratch = try temporaryDirectory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        var tree = Tree()
        let p = tree.child(of: Tree.root, kind: .package, name: "P")
        let q = tree.child(of: Tree.root, kind: .package, name: "Q")
        let model = Model(
            language: Language(name: "swift", pathSeparator: "."),
            tree: tree,
            files: [
                SourceFile(path: "Sources/P/p.swift", module: p, test: false, lines: 1),
                SourceFile(path: "Sources/Q/q.swift", module: q, test: false, lines: 2_001),
            ]
        )
        let path = scratch.appendingPathComponent("model.json")
        try ModelCodec.encode(model).write(to: path)
        let allow = scratch.appendingPathComponent("debt.allow")
        try Data("long-file Sources/Q/q.swift\n".utf8).write(to: allow)
        let scoped = try run(["check", "--model", path.path, "P", "--allow", allow.path], in: scratch)
        #expect(scoped.status == 0)
        #expect(!scoped.output.contains("now fixed"), "\(scoped.output)")
    }

    @Test("a scoped update keeps the allowed entries of what it did not check")
    func scopedUpdateKeepsTheRest() throws {
        let scratch = try temporaryDirectory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        var tree = Tree()
        let p = tree.child(of: Tree.root, kind: .package, name: "P")
        let q = tree.child(of: Tree.root, kind: .package, name: "Q")
        let model = Model(
            language: Language(name: "swift", pathSeparator: "."),
            tree: tree,
            files: [
                SourceFile(path: "Sources/P/p.swift", module: p, test: false, lines: 2_001),
                SourceFile(path: "Sources/Q/q.swift", module: q, test: false, lines: 2_001),
            ]
        )
        let path = scratch.appendingPathComponent("model.json")
        try ModelCodec.encode(model).write(to: path)
        let allow = scratch.appendingPathComponent("debt.allow")
        try Data("long-file Sources/Q/q.swift\nlong-file Sources/Gone/gone.swift\n".utf8).write(to: allow)
        let updated = try run(["check", "--model", path.path, "P", "--update-allow", allow.path], in: scratch)
        #expect(updated.status == 0, "\(updated.error)")
        let entries = try String(contentsOf: allow, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(entries == ["long-file Sources/P/p.swift", "long-file Sources/Q/q.swift"])
        #expect(try run(["check", "--model", path.path, "--allow", allow.path], in: scratch).status == 0)
    }

    @Test("an Xcode project's directory is checked as a package's is", .enabled(if: Platform.hasXcode))
    func xcodeProject() throws {
        let (project, scratch) = try fixture("Xcode")
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let result = try run([], in: project)
        #expect(result.status == 1, "\(result.error)")
        #expect(result.output.contains("error[field-leak]: `RunQueue.items` is known outside `RunQueue`"))
        #expect(lastLine(result.output) == "deslop: 1 error, well done!")
        let scoped = try run(["--scheme", "Tool"], in: project)
        #expect(scoped.status == 1, "\(scoped.error)")
    }

    @Test("Xcode options on a Swift package are a usage error")
    func xcodeOptionsOnAPackage() throws {
        let (package, scratch) = try fixture("Clean")
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: scratch) } }
        let result = try run(["--scheme", "Clean"], in: package)
        #expect(result.status == 2)
        #expect(result.error.contains("Xcode options apply to an Xcode project"))
        let none = try run([], in: scratch)
        #expect(none.status == 2)
        #expect(none.error.contains("not a Swift package (no Package.swift) nor an Xcode project or workspace"))
    }
}
