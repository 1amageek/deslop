import Testing
@testable import DeslopCore

@Suite("allowlist")
struct AllowListTests {
    private func diagnostic(_ lint: Lint, _ key: String) -> Diagnostic {
        Diagnostic(lint: lint, key: key, message: "", location: nil, notes: [], picture: .circle(steps: [], rest: nil))
    }

    @Test("shrinking an allowed tangle stays allowed")
    func shrinkingTangle() throws {
        let allow = try AllowList(parsing: "tangle a::X,a::Y,b::Z\n")
        #expect(allow.allows(diagnostic(.tangle, "a::X,b::Z")))
        #expect(!allow.allows(diagnostic(.tangle, "a::W,a::X,a::Y,b::Z")))
        #expect(allow.fixedCount([diagnostic(.tangle, "a::X,a::Y")]) == 0)
        #expect(allow.fixedCount([]) == 1)
    }

    @Test("shrinking an allowed module cycle stays allowed")
    func shrinkingCycle() throws {
        let allow = try AllowList(parsing: "module-cycle a::x,a::y,a::z\n")
        #expect(allow.allows(diagnostic(.moduleCycle, "a::x,a::z")))
        #expect(!allow.allows(diagnostic(.moduleCycle, "a::w,a::x")))
        #expect(!allow.allows(diagnostic(.tangle, "a::x,a::z")))
    }

    @Test("a comma inside a member's name splits nothing")
    func bracketedComma() throws {
        let allow = try AllowList(parsing: "tangle a::<(A, B) as T>::run,a::X,a::Y\n")
        #expect(allow.allows(diagnostic(.tangle, "a::<(A, B) as T>::run,a::Y")))
        #expect(!allow.allows(diagnostic(.tangle, "a::<(A, C) as T>::run,a::Y")))
        #expect(!allow.allows(diagnostic(.tangle, "a::Y,a::Z")))
    }

    @Test("an unknown lint is an invalid entry")
    func unknownLint() {
        #expect(throws: AllowListError.invalidEntry(line: 2)) {
            try AllowList(parsing: "field-leak a::T::x\nchatty-seam a -> b\n")
        }
    }

    @Test("the written allowlist reads back the same, sorted by lint and key")
    func roundTrip() throws {
        let diagnostics = [diagnostic(.fieldLeak, "b"), diagnostic(.moduleCycle, "z"), diagnostic(.fieldLeak, "a")]
        let text = AllowList(diagnostics: diagnostics).text(tool: "deslop")
        #expect(text.hasSuffix("module-cycle z\nfield-leak a\nfield-leak b\n"))
        #expect(try AllowList(parsing: text) == AllowList(diagnostics: diagnostics))
    }
}

@Suite("allowlist reading")
struct AllowListReadingTests {
    private func diagnostic(_ lint: Lint, _ key: String) -> Diagnostic {
        Diagnostic(lint: lint, key: key, message: "", location: nil, notes: [], picture: .circle(steps: [], rest: nil))
    }

    @Test("CRLF line breaks split entries, and an invalid one is still refused")
    func crlf() throws {
        let allow = try AllowList(parsing: "# header\r\ntangle a.X,a.Y\r\nfield-leak a.T.x\r\n")
        #expect(allow.count == 2)
        #expect(allow.allows(diagnostic(.fieldLeak, "a.T.x")))
        #expect(throws: AllowListError.invalidEntry(line: 2)) {
            try AllowList(parsing: "tangle a.X,a.Y\r\nbogus-lint x\r\n")
        }
    }

    @Test("an operator's lone angle bracket splits like any other character")
    func operatorMember() throws {
        let allow = try AllowList(parsing: "tangle P.a.<(_:_:),P.b.f,P.b.g\n")
        #expect(allow.allows(diagnostic(.tangle, "P.a.<(_:_:),P.b.f")))
        #expect(!allow.allows(diagnostic(.tangle, "P.a.<(_:_:),P.c.h")))
        #expect(AllowList.members("P.a.>(_:_:),P.b.f") == ["P.a.>(_:_:)", "P.b.f"])
        #expect(AllowList.members("a::<(A, B) as T>::run,a::Y") == ["a::<(A, B) as T>::run", "a::Y"])
    }
}
