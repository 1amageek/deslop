import Testing
@testable import DeslopSwift

/// What a demangled signature says of what a declaration takes and returns.
@Suite("demangled signatures")
struct SignatureTests {
    @Test("parameters are read with their labels, and the result after the arrow")
    func parameters() {
        let pass = Signature(text: "main.pass(_: Swift.KeyPath<main.Q, [Swift.Int]>, flag: Swift.Bool) -> Swift.KeyPath<main.Q, [Swift.Int]>")
        #expect(pass.parameters?.map(\.label) == [nil, "flag"])
        #expect(pass.result == ["Swift.KeyPath", "<", "main.Q", ",", "[", "Swift.Int", "]", ">"])
        let effects = Signature(text: "main.eff<A>(of: A, _: (A) -> main.Q) async throws -> [A]")
        #expect(effects.parameters?.map(\.label) == ["of", nil])
        #expect(effects.result == ["[", "A", "]"])
        let extended = Signature(text: "(extension in Lib):Swift.Array.firstOf() -> A?")
        #expect(extended.parameters == [])
        #expect(Signature(text: "main.Box.value : A").parameters == nil)
        let some = Signature(text: "Swift.Optional.some(A?.Type) -> (A) -> A?")
        #expect(some.parameters == [Signature.Parameter(label: nil, type: ["A"])])
        #expect(some.result == ["A", "?"])
        #expect(Signature(text: "main.H.handler : (Swift.KeyPath<main.Q, [Swift.Int]>) -> Swift.Int").parameters?.count == 1)
    }

    @Test("an argument may come back when the result names its parameter's type")
    func mayReturn() {
        let id = Signature(text: "main.id<A>(A) -> A")
        #expect(id.mayReturn(argument: 0, of: [nil], closure: false))
        let pass = Signature(text: "main.pass(_: Swift.KeyPath<main.Q, [Swift.Int]>, flag: Swift.Bool) -> Swift.KeyPath<main.Q, [Swift.Int]>")
        #expect(pass.mayReturn(argument: 0, of: [nil], closure: false))
        #expect(!pass.mayReturn(argument: 1, of: [nil, "flag"], closure: false))
        let many = Signature(text: "main.many(_: A..., into: inout [Swift.Int]) -> [A]")
        #expect(many.mayReturn(argument: 2, of: [nil, nil, nil, "into"], closure: false))
        #expect(!many.mayReturn(argument: 3, of: [nil, nil, nil, "into"], closure: false))
        let map = Signature(text: "main.map<A>((main.Q) -> A) -> [A]")
        #expect(!map.mayReturn(argument: 0, of: [nil], closure: false))
        #expect(map.mayReturn(argument: 0, of: [nil], closure: true))
        #expect(map.mayReturnFromTrailingClosure())
        #expect(!Signature(text: "main.run(_: () -> A) -> ()").mayReturnFromTrailingClosure())
        // Not a parameter it has: may be anything.
        #expect(id.mayReturn(argument: 1, of: [nil, nil], closure: false))
    }
}
