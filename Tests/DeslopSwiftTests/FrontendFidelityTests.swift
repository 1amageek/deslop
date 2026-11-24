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

    @Test("a subclass works on its superclass's fields as the superclass does")
    func subclassIsInside() throws {
        let package = try TemporaryPackage(sources: [
            "Shapes/Shapes.swift": """
                open class Base {
                    var size: Int = 0
                    private var name: String = "base"
                    public init() {}
                    open func grow() { size += 1; name += "+" }
                }
                """,
            "Square/Square.swift": """
                public final class Square: Base {
                    override public func grow() { size *= 2 }
                }
                """,
            "Client/User.swift": """
                public func reset(_ base: Base) { base.size = 0 }
                """,
        ])
        defer { clean(package) }
        // `Square` is `Base`'s; `reset` is not.
        let model = try PackageFrontend(packageRoot: package.directory).model()
        let diagnostics = Linter().check(model)
        #expect(diagnostics.map(\.key) == ["Lib.Shapes.Base.size"])
        #expect(diagnostics.first?.message == "`Base.size` is known outside `Base`: 1 place in 1 module")
        #expect(diagnostics.first?.notes.allSatisfy { !$0.contains("Square") } == true)
    }

    @Test("a member that meets a requirement of a protocol its type conforms to elsewhere implements it")
    func witnessInBody() throws {
        let methods = (0..<8).map { "    public func m\($0)() -> Int { \($0) }" }.joined(separator: "\n")
        let requirements = (0..<8).map { "    func m\($0)() -> Int" }.joined(separator: "\n")
        let package = try TemporaryPackage(sources: [
            "Steps/Steps.swift": "public protocol Steps {\n\(requirements)\n}\n",
            "Machine/Machine.swift": """
                public struct Machine {
                    public init() {}
                \(methods)
                    public init(from decoder: any Decoder) throws {}
                    public func extra() -> Int { 0 }
                }
                extension Machine: Steps {}
                extension Machine: Decodable {}
                """,
            "Machine/Part/Part.swift": "struct Part {}\n",
        ])
        defer { clean(package) }
        let model = try PackageFrontend(packageRoot: package.directory).model()
        let interface = Set(model.items.filter(\.implementsInterface).map(\.name))
        #expect((0..<8).allSatisfy { interface.contains("Machine.m\($0)()") })
        #expect(interface.contains("Machine.init(from:)"))
        #expect(!interface.contains("Machine.extra()"))
        #expect(!interface.contains("Machine.init()"))
    }

    @Test("a cast or a fallback passes a field on, and what is reached on it is reached on the field")
    func castAndFallback() throws {
        let package = try TemporaryPackage(sources: [
            "Store/Holder.swift": """
                public struct Inner {
                    public init() {}
                    public func go() -> Int { 1 }
                }
                public struct Holder {
                    var inner: Inner = Inner()
                    var backup: Inner? = nil
                    private var count: Int = 0
                    public init() {}
                    public mutating func work() -> Int { count += 1; return inner.go() + (backup?.go() ?? 0) }
                }
                """,
            "Client/User.swift": """
                public func cast(_ h: Holder) -> Int { (h.inner as Inner).go() }
                public func fallback(_ h: Holder) -> Int { (h.backup ?? Inner()).go() }
                public func read(_ h: Holder) -> Inner? { h.backup ?? nil }
                """,
        ])
        defer { clean(package) }
        #expect(try keys(package) == ["field-leak Lib.Store.Holder.backup", "field-leak Lib.Store.Holder.inner"])
    }

    @Test("a key path declared writable writes the field it names; one only read reads it")
    func writableKeyPath() throws {
        let package = try TemporaryPackage(sources: [
            "Store/Queue.swift": """
                public struct Queue {
                    var items: [Int] = []
                    var label: String = ""
                    private var head: Int = 0
                    public init() {}
                    public mutating func pop() -> Int? { head += 1; return items.dropFirst(head - 1).first }
                }
                """,
            "Client/User.swift": """
                public func clear(_ q: inout Queue) {
                    let path: WritableKeyPath<Queue, [Int]> = \\.items
                    q[keyPath: path].removeAll()
                }
                public func labels(_ queues: [Queue]) -> [String] {
                    queues.map(\\.label)
                }
                """,
        ])
        defer { clean(package) }
        #expect(try keys(package) == ["field-leak Lib.Store.Queue.items"])
    }
}
