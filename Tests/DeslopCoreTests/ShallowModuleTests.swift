import DeslopModel
import Testing
@testable import DeslopCore

@Suite("shallow-module")
struct ShallowModuleTests {
    /// `store`, with a child module, whose `Store` has `shown` methods that
    /// `app` calls and `hidden` that only `Store` calls.
    private func store(_ shown: Int, _ hidden: Int) -> Sample {
        var sample = Sample()
        let (store, app) = (sample.module("store"), sample.module("app"))
        _ = sample.module("store::table")
        let type = sample.item(store, "Store", .type)
        let run = sample.item(app, "run", .function)
        let helpers = (0..<hidden).map { sample.member(type, store, "Store::helper\($0)", .function) }
        for index in 0..<shown {
            let method = sample.member(type, store, "Store::m\(index)", .function)
            sample.refer(run, method)
            for helper in helpers { sample.refer(method, helper) }
        }
        return sample
    }

    /// `store`, with a child module, that hides nothing and shows to `app` a
    /// type `T{i}` with `widths[i]` methods for each `i`, and `free` free functions `f{i}`.
    private func things(_ widths: [Int], free: Int) -> Sample {
        var sample = Sample()
        let (store, app) = (sample.module("store"), sample.module("app"))
        _ = sample.module("store::table")
        let run = sample.item(app, "run", .function)
        for (typeIndex, width) in widths.enumerated() {
            let type = sample.item(store, "T\(typeIndex)", .type)
            for index in 0..<width {
                let method = sample.member(type, store, "T\(typeIndex)::m\(index)", .function)
                sample.refer(run, method)
            }
        }
        for index in 0..<free {
            let function = sample.item(store, "f\(index)", .function)
            sample.refer(run, function)
        }
        return sample
    }

    /// Adds to `store` a free function `name` that `app` calls and whose code uses each of `types`.
    private func knowing(_ sample: inout Sample, _ name: String, _ types: [String]) {
        let store = sample.module("store")
        let function = sample.item(store, name, .function)
        sample.refer(sample.named("run"), function)
        for type in types {
            sample.refer(function, sample.named(type))
        }
    }

    private func keys(_ sample: Sample) -> [String] {
        ShallowModuleRule().check(sample.context()).map(\.key)
    }

    private func notes(_ sample: Sample) -> [String] {
        let diagnostics = ShallowModuleRule().check(sample.context())
        #expect(diagnostics.count == 1)
        return diagnostics.first?.notes ?? []
    }

    @Test("a module that shows more than it hides and more than seven is shallow")
    func shallow() {
        #expect(keys(store(8, 8)) == ["p::store"])
        #expect(ShallowModuleRule().check(store(8, 8).context())[0].picture == .lists(
            shown: 8, hidden: 8, lists: [Picture.Bar(name: "Store", length: 8)]
        ))
        #expect(keys(store(8, 9)).isEmpty)
        #expect(keys(store(7, 0)).isEmpty)
    }

    @Test("seven is a limit on each list, not on their sum")
    func limitOnEachList() {
        #expect(keys(things([5, 5, 5], free: 0)).isEmpty)
        #expect(keys(things([5, 4, 3], free: 1)).isEmpty)
        #expect(keys(things(Array(repeating: 7, count: 7), free: 0)).isEmpty)
        #expect(keys(things([], free: 7)).isEmpty)
        #expect(keys(things([], free: 8)) == ["p::store"])
        #expect(keys(things([8], free: 0)) == ["p::store"])
    }

    @Test("the notes name each list that is too long, the things first, then the widest")
    func notesNameLongLists() {
        #expect(notes(things([2, 8], free: 5)) == [
            "`T1` shows 8 functions: T1::m0, T1::m1, T1::m2, T1::m3, T1::m4, T1::m5, T1::m6, +1 more",
        ])
        #expect(notes(things([8, 9, 9], free: 5)) == [
            "shows 8 things: T1, T2, T0, f0, f1, f2, f3, +1 more",
            "`T1` shows 9 functions: T1::m0, T1::m1, T1::m2, T1::m3, T1::m4, T1::m5, T1::m6, +2 more",
            "`T2` shows 9 functions: T2::m0, T2::m1, T2::m2, T2::m3, T2::m4, T2::m5, T2::m6, +2 more",
            "`T0` shows 8 functions: T0::m0, T0::m1, T0::m2, T0::m3, T0::m4, T0::m5, T0::m6, +1 more",
        ])
        #expect(notes(things([1], free: 7)) == ["shows 8 things: T0, f0, f1, f2, f3, f4, f5, +1 more"])
    }

    @Test("a free function is on the list of each type of the module it knows")
    func freeFunctionOnTypeLists() {
        var sample = things([6], free: 0)
        knowing(&sample, "fa", ["T0"])
        knowing(&sample, "fb", ["T0"])
        #expect(keys(sample) == ["p::store"])
        #expect(keys(things([6], free: 2)).isEmpty)

        var both = things([6, 6], free: 0)
        knowing(&both, "both", ["T0", "T1"])
        knowing(&both, "first", ["T0"])
        knowing(&both, "second", ["T1"])
        #expect(notes(both) == [
            "`T0` shows 8 functions: T0::m0, T0::m1, T0::m2, T0::m3, T0::m4, T0::m5, both, +1 more",
            "`T1` shows 8 functions: T1::m0, T1::m1, T1::m2, T1::m3, T1::m4, T1::m5, both, +1 more",
        ])
    }

    @Test("a free function that knows no type of the module is a thing of its own")
    func freeFunctionOfItsOwn() {
        var sample = things([], free: 7)
        let app = sample.module("app")
        _ = sample.item(app, "Outside", .type)
        knowing(&sample, "e", ["Outside"])
        #expect(notes(sample) == ["shows 8 things: e, f0, f1, f2, f3, f4, f5, +1 more"])
    }

    @Test("lists that share a free function never make a module shallow that shows seven")
    func sharedFreeFunction() {
        var sample = things(Array(repeating: 0, count: 8), free: 0)
        knowing(&sample, "build", (0..<8).map { "T\($0)" })
        #expect(keys(sample).isEmpty)
    }

    @Test("wrappers count for nothing, and a method counts at its type's home")
    func wrappersCountForNothing() {
        var sample = store(8, 8)
        let type = ItemID(0)
        let (store, app) = (sample.module("store"), sample.module("app"))
        for index in 0..<8 {
            let forwarder = sample.member(type, store, "Store::pad\(index)", .function)
            sample.model.wrappers[forwarder] = .forwarder(target: ItemID(3), fields: [])
        }
        let moved = sample.member(type, app, "Store::moved", .function)
        sample.refer(ItemID(1), moved)
        let diagnostics = ShallowModuleRule().check(sample.context())
        #expect(diagnostics[0].message == "`p::store` is shallow: it shows 9 of its 17 functions")
    }
}
