import Foundation
import Testing
@testable import DeslopSwift

/// What code does with a field a key path names, followed through the
/// code around the key path; what the index would say of the names there is
/// given by their text.
@Suite("key path flow")
struct KeyPathFlowTests {
    /// What the code of `body` does with `field`, which the first key path
    /// `\Q.<field>` in it names. Names in `readOnly` declare no writable key
    /// path, those in `writable` declare one; the index names nothing else.
    private func access(
        _ body: String,
        _ field: String = "items",
        readOnly: Set<String> = [],
        writable: Set<String> = []
    ) throws -> Access {
        let text = "func f() {\n\(body)\n}\n"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let marker = "\\Q.\(field)"
        let line = try #require(lines.firstIndex { $0.contains(marker) })
        let column = try #require(lines[line].range(of: marker)).upperBound.utf16Offset(in: lines[line]) - field.utf16.count + 1
        let syntax = SourceSyntax(text: text, fileName: "f.swift")
        let name = { (at: SourcePosition) -> String in
            String(lines[at.line - 1].utf8.dropFirst(at.column - 1).prefix { byte in
                byte != UInt8(ascii: " ") && byte != UInt8(ascii: "(") && byte != UInt8(ascii: ")")
            }) ?? ""
        }
        let facts = NameFacts(
            isField: { _ in false },
            keyPathSignature: { at in
                let named = name(at)
                if writable.contains(named) { return .writable }
                return readOnly.contains(named) ? .readOnly : nil
            },
            keyPathFlow: { _ in nil }
        )
        return syntax.access(at: SourcePosition(line: line + 1, column: column), facts: facts)
    }

    @Test("a key path passed on is what the signature it is passed to declares")
    func passed() throws {
        #expect(try access("read(\\Q.items)", readOnly: ["read"]) == .copy)
        #expect(try access("write(\\Q.items)", writable: ["write"]) == .reach)
        #expect(try access("closure(\\Q.items)") == .reach)
        #expect(try access("let n = q[keyPath: \\Q.items]") == .copy)
        #expect(try access("q[keyPath: \\Q.items].removeAll()") == .reach)
    }

    @Test("a key path in a collection, a loop, a conditional or parentheses is what is done with the whole")
    func carried() throws {
        #expect(try access("let all = [\\Q.items]\nfor p in all { q[keyPath: p] = [] }") == .reach)
        #expect(try access("let all = [\\Q.items]\nfor p in all { let n = q[keyPath: p] }") == .copy)
        #expect(try access("let all = [\\Q.items: 1]\nall.forEach { _ in }") == .reach)
        #expect(try access("let p = c ? \\Q.items : \\Q.other\nq[keyPath: p] = []") == .reach)
        #expect(try access("let p = (\\Q.items)\nq[keyPath: p] = []") == .reach)
        #expect(try access("let p = given ?? \\Q.items\nlet n = q[keyPath: p]") == .copy)
    }

    @Test("a key path cast, compared, matched, interpolated or discarded is read")
    func read() throws {
        #expect(try access("let p = \\Q.items as KeyPath<Q, [Int]>\nq[keyPath: p] = []") == .copy)
        #expect(try access("let p = \\Q.items as WritableKeyPath<Q, [Int]>\nq[keyPath: p] = []") == .reach)
        #expect(try access("let same = p == \\Q.items", readOnly: ["=="]) == .copy)
        #expect(try access("let same = p == \\Q.items || p == \\Q.other", readOnly: ["==", "||"]) == .copy)
        #expect(try access("switch p { case \\Q.items: break; default: break }") == .copy)
        #expect(try access("print(\"\\(\\Q.items)\")", readOnly: ["print"]) == .copy)
        #expect(try access("_ = \\Q.items") == .copy)
        #expect(try access("let p = \\Q.items") == .copy)
        #expect(try access("var p = \\Q.other\np = \\Q.items") == .copy)
        #expect(try access("var p = \\Q.other\np = \\Q.items\nlet n = q[keyPath: p]") == .copy)
        #expect(try access("var p = \\Q.other\nif c { p = \\Q.items }\nq[keyPath: p] = []") == .reach)
        #expect(try access("var p = \\Q.other\nfor _ in 0..<2 { q[keyPath: p] = []; p = \\Q.items }") == .reach)
        #expect(try access("func g(p: inout KeyPath<Q, [Int]>) { p = \\Q.items }") == .reach)
        #expect(try access("var p = \\Q.other\nvar o = p\n(p, o) = (\\Q.items, p)\nlet n = q[keyPath: o]") == .copy)
        #expect(try access("var p = \\Q.other\nvar o = p\n(p, o) = (\\Q.items, p)\nq[keyPath: o] = []") == .reach)
    }

    @Test("a key path a local function or closure returns is what is done with what it returns")
    func returned() throws {
        #expect(try access("func path() -> WritableKeyPath<Q, [Int]> { \\Q.items }\nq[keyPath: path()] = []") == .reach)
        #expect(try access("func path() -> WritableKeyPath<Q, [Int]> { return \\Q.items }\nlet n = q[keyPath: path()]") == .copy)
        #expect(try access("let path = { \\Q.items }\nq[keyPath: path()] = []") == .reach)
        #expect(try access("let path = { () -> KeyPath<Q, [Int]> in \\Q.items }\nq[keyPath: path()] = []") == .copy)
        #expect(try access("let p = if c { \\Q.items } else { \\Q.other }\nq[keyPath: p] = []") == .reach)
    }
}
