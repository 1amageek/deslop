import DeslopCore
import DeslopModel
import DeslopSwift
import Foundation
import TestHeartbeat
import Testing

/// The Xcode frontend, end to end: an Xcode project with a file-system-
/// synchronized app target and a test target, built with its index.
@Suite("Xcode frontend, end to end", .heartbeat, .timeLimit(.minutes(10)))
struct XcodeFrontendTests {
    @Test("an Xcode project is checked as a package is, with test code left out")
    func project() throws {
        let fixture = try Fixture("Xcode")
        defer {
            do { try fixture.remove() } catch { Issue.record("could not remove \(fixture.directory.path): \(error)") }
        }
        let model = try XcodeFrontend(root: fixture.directory).model()
        let keys = Linter().check(model).map { "\($0.lint.name) \($0.key)" }
        // `ToolTests` writes `head` too, and is left out.
        #expect(keys == ["field-leak Tool.Queue.RunQueue.items"])
        #expect(model.files.filter(\.test).map(\.path) == ["ToolTests/PeekTests.swift"])
        #expect(model.files.first { $0.path == "Tool/main.swift" }?.rank == 0)
    }

    @Test("a project that does not build is an error naming what failed")
    func buildError() throws {
        let fixture = try Fixture("Xcode")
        defer {
            do { try fixture.remove() } catch { Issue.record("could not remove \(fixture.directory.path): \(error)") }
        }
        try Data("let broken: Int = \"text\"\n".utf8).write(to: fixture.directory.appendingPathComponent("Tool/Broken.swift"))
        do {
            _ = try XcodeFrontend(root: fixture.directory).model()
            Issue.record("a project that does not build made a model")
        } catch {
            guard case .commandFailed(_, _, let output) = error else {
                Issue.record("expected a failed build, got \(error)")
                return
            }
            #expect(output.contains("Broken.swift"))
        }
    }

    @Test("a scheme that is not the project's is refused")
    func unknownScheme() throws {
        let fixture = try Fixture("Xcode")
        defer {
            do { try fixture.remove() } catch { Issue.record("could not remove \(fixture.directory.path): \(error)") }
        }
        #expect(throws: FrontendError.schemeNotFound(scheme: "Nope", available: ["Tool"])) {
            try XcodeFrontend(root: fixture.directory, schemes: ["Nope"]).model()
        }
    }
}
