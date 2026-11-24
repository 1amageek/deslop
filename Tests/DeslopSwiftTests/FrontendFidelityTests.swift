import DeslopCore
import DeslopModel
import DeslopSwift
import Foundation
import TestHeartbeat
import Testing

/// Swift constructs whose model must say what the code does, so that the
/// lints neither miss a mistake nor flag sound code.
@Suite("Swift frontend fidelity", .heartbeat, .timeLimit(.minutes(10)))
struct FrontendFidelityTests {
    /// A type that keeps `count` to itself and works on `inner`, and code
    /// outside it in another module that reaches into `inner`.
    private static let leakOfInner = """
        public struct Inner {
            public init() {}
            public mutating func go() {}
        }
        """

    private func keys(_ package: TemporaryPackage, buildsIndex: Bool = true) throws -> [String] {
        let model = try PackageFrontend(packageRoot: package.directory, buildsIndex: buildsIndex).model()
        return Linter().check(model).map { "\($0.lint.name) \($0.key)" }.sorted()
    }

    private func clean(_ package: TemporaryPackage) {
        do { try package.remove() } catch { Issue.record("could not remove \(package.directory.path): \(error)") }
    }

    @Test("a field whose type its initial value says is as typed as one written out")
    func inferredTypes() throws {
        let package = try TemporaryPackage(sources: [
            "Store/Inner.swift": FrontendFidelityTests.leakOfInner,
            "Store/Holder.swift": """
                public struct Holder {
                    var inner = Inner()
                    var offset = -1
                    private var count: Int = 0
                    public init() {}
                    public var view: Inner { inner }
                    public mutating func work() { inner.go(); count += offset }
                }
                """,
            "Client/User.swift": """
                public func use(_ holder: Holder) -> Int {
                    var copy = holder.view
                    copy.go()
                    return holder.offset.signum()
                }
                public func reach(_ holder: inout Holder) {
                    holder.inner.go()
                }
                """,
        ])
        defer { clean(package) }
        // `view` hands out `inner`, so `holder.view` is a read of it; `offset`
        // is an `Int`, so a member of it is read, not reached.
        #expect(try keys(package) == ["field-leak Lib.Store.Holder.inner"])
    }

    @Test("each name of a tuple pattern is a field")
    func tuplePattern() throws {
        let package = try TemporaryPackage(sources: [
            "Store/Pair.swift": """
                public struct Pair {
                    var (left, right): ([Int], [Int]) = ([0], [1])
                    private var kept: Int = 0
                    public init() {}
                    public mutating func swap() { (left, right) = (right, left); kept += 1 }
                }
                """,
            "Client/User.swift": """
                public func grow(_ pair: inout Pair) {
                    pair.left.append(9)
                }
                """,
        ])
        defer { clean(package) }
        #expect(try keys(package) == ["field-leak Lib.Store.Pair.left"])
    }

    @Test("a file that starts with a byte order mark keeps the declarations of its first line")
    func byteOrderMark() throws {
        let package = try TemporaryPackage(sources: [
            "Store/Bom.swift": "\u{FEFF}public struct Bom { public var a: Int = 0; public init() {} }\n",
            "Client/User.swift": "public func read(_ bom: Bom) -> Int { bom.a }\n",
        ])
        defer { clean(package) }
        let model = try PackageFrontend(packageRoot: package.directory).model()
        #expect(model.items.map(\.name).contains("Bom.a"))
        #expect(model.references.contains { model.item($0.item).name == "Bom.a" })
    }

    @Test("a source changed since the last build is an error, not a model of what it was")
    func staleIndex() throws {
        let package = try TemporaryPackage(sources: ["Store/Ready.swift": "public struct Ready { public init() {} }\n"])
        defer { clean(package) }
        _ = try PackageFrontend(packageRoot: package.directory).model()
        let file = package.url("Sources/Lib/Store/Ready.swift")
        try Data("// moved\npublic struct Ready { public init() {} }\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        #expect(throws: FrontendError.indexStale(path: "Sources/Lib/Store/Ready.swift")) {
            try PackageFrontend(packageRoot: package.directory, buildsIndex: false).model()
        }
    }

    @Test("a target's root file is named after the target, in any case")
    func rootFileCase() throws {
        let package = try TemporaryPackage(target: "tool", sources: ["Tool.swift": "public func run() {}\n"])
        defer { clean(package) }
        let model = try PackageFrontend(packageRoot: package.directory).model()
        #expect(model.files.first?.rank == 0)
        #expect(model.files.first?.declares == "Sources/tool")
    }
}
