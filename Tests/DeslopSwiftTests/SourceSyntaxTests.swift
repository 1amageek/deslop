import Foundation
import Testing
@testable import DeslopSwift

@Suite("Swift syntax facts")
struct SourceSyntaxTests {
    /// What the code at the first occurrence of `marker` in `line` does with
    /// the name there; `fields` are the member names that are stored fields.
    private func access(_ line: String, _ marker: String, fields: Set<String> = [], call: Bool = false) throws -> Access {
        let text = "func f() {\n\(line)\n}\n"
        let syntax = SourceSyntax(text: text, fileName: "f.swift")
        let column = try #require(line.range(of: marker)).lowerBound.utf16Offset(in: line) + 1
        let position = SourcePosition(line: 2, column: column)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let isField = { (at: SourcePosition) -> Bool in
            let text = lines[at.line - 1].utf8.dropFirst(at.column - 1)
            return fields.contains { String(decoding: text, as: UTF8.self).hasPrefix($0) }
        }
        let facts = NameFacts(isField: isField, takesWritableKeyPath: { _ in false })
        return call ? syntax.callAccess(at: position, facts: facts) : syntax.access(at: position, facts: facts)
    }

    @Test("using a field's value reads it")
    func copy() throws {
        #expect(try access("let x = queue.head + 1", "head") == .copy)
        #expect(try access("return (queue.head)", "head") == .copy)
        #expect(try access("g(queue.head)", "head") == .copy)
    }

    @Test("reaching a member of a field calls on it")
    func call() throws {
        #expect(try access("let n = queue.items.count", "items") == .call)
        #expect(try access("let n = queue.items?.first", "items") == .call)
        #expect(try access("let n = items.count", "items") == .call)
    }

    @Test("a field path goes on through stored fields to what is done at its end")
    func fieldPath() throws {
        #expect(try access("let n = queue.inner.items.count", "inner", fields: ["items"]) == .call)
        #expect(try access("let n = queue.inner.items + 1", "inner", fields: ["items"]) == .copy)
    }

    @Test("assigning, passing inout, or subscripting reaches")
    func reach() throws {
        #expect(try access("queue.head = 0", "head") == .reach)
        #expect(try access("queue.head += 1", "head") == .reach)
        #expect(try access("touch(&queue.head)", "head") == .reach)
        #expect(try access("let x = queue.items[0]", "items") == .reach)
        #expect(try access("let same = queue.head == 0", "head") == .copy)
    }

    @Test("what a called accessor hands out is read as a field is")
    func callAccess() throws {
        #expect(try access("let x = queue.head() + 1", "head", call: true) == .copy)
        #expect(try access("let n = queue.items().count", "items", call: true) == .call)
        #expect(try access("let f = queue.items", "items", call: true) == .reach)
    }

    @Test("stored and computed properties are told apart")
    func properties() {
        let text = """
            struct S {
                var a: Int
                var b = 0 { didSet {} }
                var c: Int { a }
                lazy var d: [Int] = []
            }
            """
        let syntax = SourceSyntax(text: text, fileName: "s.swift")
        let kinds = (2...5).map { line in syntax.declarations.first { $0.key.line == line }?.value.kind }
        #expect(kinds == [.storedProperty, .storedProperty, .computedProperty, .storedProperty])
        #expect(syntax.declarations.first { $0.key.line == 3 }?.value.declaredType == ["Int"])
    }

    @Test("a body that is one call on a field path is told by its shape")
    func onlyCall() throws {
        let text = """
            struct S {
                mutating func push(_ task: Int) { ring.push(task) }
                var count: Int { self.ring.count }
                func sum(_ a: Int) -> Int { a + 1 }
                func pass(_ a: Int) { helper(a, 1) }
            }
            """
        let syntax = SourceSyntax(text: text, fileName: "s.swift")
        func body(_ line: Int) -> FunctionBody? {
            guard let position = syntax.declarations.keys.first(where: { $0.line == line }) else { return nil }
            return syntax.body(at: position)
        }
        let push = try #require(body(2)?.onlyCall)
        #expect(push.base == .implicitSelf)
        #expect(push.path.count == 1)
        #expect(push.arguments == ["task"])
        #expect(push.isCall)
        let count = try #require(body(3)?.onlyCall)
        #expect(count.base == .selfValue)
        #expect(!count.isCall)
        #expect(body(4)?.onlyCall == nil)
        #expect(body(4)?.computes == true)
        #expect(body(5)?.onlyCall?.arguments == ["a", nil])
    }

    @Test("a file's lines are every line, the last without a break too")
    func lineCount() {
        #expect(PackageLayout.lineCount("") == 0)
        #expect(PackageLayout.lineCount("a\n") == 1)
        #expect(PackageLayout.lineCount("a\n\nb") == 3)
        #expect(PackageLayout.lineCount("a\r\nb\r\n") == 2)
    }
}
