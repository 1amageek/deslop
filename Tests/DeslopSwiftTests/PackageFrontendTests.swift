import DeslopCore
import DeslopModel
import DeslopSwift
import TestHeartbeat
import Testing

/// The Swift frontend, end to end: Swift ports of deslop-please's fixtures,
/// built with their index, turned into the model, and linted.
@Suite("Swift frontend, end to end", .heartbeat, .timeLimit(.minutes(10)))
struct PackageFrontendTests {
    private struct Run {
        let model: Model
        let diagnostics: [Diagnostic]

        var keys: [String] { diagnostics.map { "\($0.lint.name) \($0.key)" }.sorted() }

        func report() -> String {
            Renderer(tool: "deslop", colored: false).render(diagnostics)
        }
    }

    private func lint(_ family: String, variant: String? = nil) throws -> Run {
        let fixture = try Fixture(family, variant: variant)
        defer {
            do { try fixture.remove() } catch { Issue.record("could not remove \(fixture.directory.path): \(error)") }
        }
        let model = try PackageFrontend(packageRoot: fixture.directory).model()
        return Run(model: model, diagnostics: Linter().check(model))
    }

    @Test("a leaked field leaks however it is reached, and not once the type does the work")
    func fieldLeak() throws {
        let run = try lint("FieldLeak")
        let report = run.report()
        #expect(report.contains("error[field-leak]: `RunQueue.items` is known outside `RunQueue`: 4 places in 2 modules"))
        #expect(report.contains("""
                RunQueue.Queue.RunQueue
                  items ◀━┳━ 2  RunQueue.Sched.Policy
                          ┗━ 2  RunQueue.Sched.Report
                  also known outside: head
                  kept: limit

            """))
        #expect(run.keys == ["field-leak RunQueue.Queue.RunQueue.head", "field-leak RunQueue.Queue.RunQueue.items"])
        // Behind computed properties, the stored fields leak as the fields did.
        #expect(try lint("FieldLeak", variant: "getters").keys == [
            "field-leak RunQueue.Queue.RunQueue.cursor", "field-leak RunQueue.Queue.RunQueue.storage",
        ])
        // The work moved into the type, or into a type behind a field that it
        // passes each call on to; and reading a value works on nothing.
        for variant in ["real", "passedOn", "read"] {
            #expect(try lint("FieldLeak", variant: variant).keys.isEmpty, "\(variant)")
        }
    }

    @Test("test code is left out of the model's things")
    func testCodeLeftOut() throws {
        let run = try lint("FieldLeak")
        let testFiles = run.model.files.filter(\.test)
        #expect(testFiles.map(\.path) == ["Tests/RunQueueTests/PeekTests.swift"])
        let found = run.model.files.firstIndex { $0.test }
        let testFile = try #require(found)
        #expect(!run.model.references.contains { $0.file.index == testFile && !$0.test })
    }

    @Test("a module cycle stays one until the code moves where it is used")
    func moduleCycle() throws {
        let run = try lint("ModuleCycle")
        let report = run.report()
        #expect(report.contains("error[module-cycle]: 2 modules in `Net` use each other in a circle"))
        #expect(!report.contains("error[tangle]"))
        #expect(report.contains("""
                ┌─▶ Kinds
                │     ┃ Kinds/Stream.swift:6   Stream.init(backlog:) uses backlogMost
                │     ▼
                │   Socket
                │     │ Socket/Socket.swift:3  listen(_:) uses Stream.{self, init(backlog:)}
                └─────┘

            """))
        #expect(run.keys == ["module-cycle Net.Kinds,Net.Socket"])
        #expect(try lint("ModuleCycle", variant: "moved").keys.isEmpty)
    }

    @Test("a tangle across modules is one, and is none once it is one module")
    func tangle() throws {
        let run = try lint("Tangle")
        #expect(run.report().contains("error[tangle]: 2 things know each other in a circle, across 2 modules"))
        #expect(run.keys == [
            "module-cycle Boot.Kernel.Tasks,Boot.Kernel.Timers",
            "tangle Boot.Kernel.Tasks.Tasks,Boot.Kernel.Timers.Timers",
        ])
        #expect(try lint("Tangle", variant: "merged").keys.isEmpty)
    }

    @Test("a shallow module stays shallow until it does more with less")
    func shallow() throws {
        let report = try lint("Shallow").report()
        #expect(report.contains("error[shallow-module]: `Inventory.Store` is shallow: it shows 9 of its 14 functions"))
        #expect(report.contains(
            "= note: `Store` shows 9 functions: Store.contains(_:), Store.get(_:), Store.init(limit:), "
                + "Store.insert(_:_:), Store.isFull, Store.largest, Store.remove(_:), +2 more"
        ))
        #expect(report.contains("""
                              7
                shows  ███████│██ 9
                hides  █████  │ 5
                Store  ███████│██ 9

            """))
        #expect(try lint("Shallow", variant: "deep").keys.isEmpty)
    }

    @Test("a clean package reports nothing")
    func clean() throws {
        let run = try lint("Clean")
        #expect(run.diagnostics.isEmpty)
        #expect(run.model.items.map(\.name).sorted() == ["Ready", "Ready.init()", "send()", "sendNow()"])
    }

    @Test("without a build, a package whose index is missing is an error, not a clean model")
    func missingIndex() throws {
        let fixture = try Fixture("Clean")
        defer {
            do { try fixture.remove() } catch { Issue.record("could not remove \(fixture.directory.path): \(error)") }
        }
        #expect(throws: FrontendError.self) {
            try PackageFrontend(packageRoot: fixture.directory, buildsIndex: false).model()
        }
    }
}
