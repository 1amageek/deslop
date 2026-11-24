import DeslopModel
import Testing
@testable import DeslopCore

@Suite("field-leak")
struct FieldLeakTests {
    /// `RunQueue { items, head, limit }` in `queue`, whose `full(&self)`
    /// reads every field, and a scheduler in `sched` whose `admit` uses `items`.
    private func queue() -> (sample: Sample, admit: ItemID, head: ItemID) {
        var sample = Sample()
        let (queue, sched) = (sample.module("queue"), sample.module("sched"))
        let runQueue = sample.item(queue, "RunQueue", .type)
        let fields = ["items", "head", "limit"].map { sample.member(runQueue, queue, "RunQueue::\($0)", .field) }
        let full = sample.member(runQueue, queue, "RunQueue::full", .function)
        sample.setTakesSelf(full)
        for field in fields { sample.refer(full, field) }
        let admit = sample.item(sched, "admit", .function)
        sample.refer(admit, fields[0])
        return (sample, admit, fields[1])
    }

    private func keys(_ sample: Sample) -> [String] {
        FieldLeakRule().check(sample.context()).map(\.key).sorted()
    }

    @Test("a field an outsider uses leaks from a struct that guards its others")
    func leaks() {
        let (sample, _, _) = queue()
        #expect(keys(sample) == ["p::queue::RunQueue::items"])
        #expect(FieldLeakRule().check(sample.context())[0].picture == .spread(
            owner: "p::queue::RunQueue",
            field: "items",
            modules: [Picture.Spread(places: 1, module: "p::sched")],
            others: ["kept: head, limit"]
        ))
    }

    @Test("a getter is seen through, and free code in the same file is an outsider")
    func getterSeenThrough() {
        var (sample, admit, head) = queue()
        let queueModule = sample.model.item(head).owner
        let runQueue = sample.model.item(head).parent!
        let getter = sample.member(runQueue, queueModule, "RunQueue::head", .function)
        sample.refer(getter, head)
        sample.model.wrappers[getter] = .accessor(lent: [head], copied: [], toRead: true)
        let drained = sample.item(queueModule, "drained", .function)
        sample.refer(drained, getter)
        sample.refer(admit, getter)
        #expect(keys(sample) == ["p::queue::RunQueue::head", "p::queue::RunQueue::items"])
        sample.model.wrappers[getter] = .accessor(lent: [], copied: [head], toRead: true)
        #expect(keys(sample) == ["p::queue::RunQueue::items"])
    }

    @Test("a borrow a getter lends is no leak where its caller only reads it")
    func lentRead() {
        var (sample, admit, head) = queue()
        let queueModule = sample.model.item(head).owner
        let runQueue = sample.model.item(head).parent!
        let getter = sample.member(runQueue, queueModule, "RunQueue::head", .function)
        sample.refer(getter, head)
        sample.model.wrappers[getter] = .accessor(lent: [head], copied: [], toRead: true)
        sample.read(admit, getter)
        #expect(keys(sample) == ["p::queue::RunQueue::items"])
        sample.refer(admit, getter)
        #expect(keys(sample) == ["p::queue::RunQueue::head", "p::queue::RunQueue::items"])
    }

    @Test("taking a copy of a field is no leak, but the field is not kept")
    func copyIsNoLeak() {
        var (sample, admit, head) = queue()
        sample.read(admit, head)
        #expect(keys(sample) == ["p::queue::RunQueue::items"])
        sample.read(admit, ItemID(head.index + 1))
        #expect(keys(sample).isEmpty)
    }

    @Test("a marker field is not one a struct keeps")
    func markerField() {
        var (sample, admit, head) = queue()
        let limit = ItemID(head.index + 1)
        sample.refer(admit, head)
        let queueModule = sample.model.item(head).owner
        let runQueue = sample.model.item(head).parent!
        let marker = sample.member(runQueue, queueModule, "RunQueue::_owner", .field)
        sample.model.items[marker.index].holdsNothing = true
        #expect(keys(sample) == ["p::queue::RunQueue::head", "p::queue::RunQueue::items"])
        sample.refer(admit, limit)
        #expect(keys(sample).isEmpty)
    }

    @Test("a struct that keeps nothing or does nothing guards nothing")
    func guardsNothing() {
        var (sample, admit, head) = queue()
        sample.refer(admit, head)
        sample.refer(admit, ItemID(head.index + 1))
        #expect(keys(sample).isEmpty)
        var (idle, _, _) = queue()
        for index in idle.model.items.indices { idle.model.items[index].takesSelf = false }
        #expect(keys(idle).isEmpty)
    }
}

@Suite("field-leak and inheritance")
struct FieldLeakInheritanceTests {
    /// `Base { size, name }` in `shapes`, whose `grow` works on both, and
    /// `Square`, which inherits `Base`'s implementation, in `square`.
    private func shapes(inherits: Bool) -> Sample {
        var sample = Sample()
        let (shapes, square) = (sample.module("shapes"), sample.module("square"))
        let base = sample.item(shapes, "Base", .type)
        let size = sample.member(base, shapes, "Base::size", .field)
        let name = sample.member(base, shapes, "Base::name", .field)
        let grow = sample.member(base, shapes, "Base::grow", .function)
        sample.setTakesSelf(grow)
        sample.refer(grow, size)
        sample.refer(grow, name)
        let squareType = sample.item(square, "Square", .type)
        if inherits { sample.model.items[squareType.index].inherits = [base] }
        let override = sample.member(squareType, square, "Square::grow", .function)
        sample.setTakesSelf(override)
        sample.refer(override, size)
        return sample
    }

    @Test("a type that inherits another's implementation is inside it, as its subclass")
    func subclassIsInside() {
        #expect(FieldLeakRule().check(shapes(inherits: false).context()).map(\.key) == ["p::shapes::Base::size"])
        #expect(FieldLeakRule().check(shapes(inherits: true).context()).isEmpty)
    }

    @Test("what inherits from an inheritor is inside too")
    func transitive() {
        var sample = shapes(inherits: true)
        let leaf = sample.module("leaf")
        let tiny = sample.item(leaf, "Tiny", .type)
        sample.model.items[tiny.index].inherits = [sample.named("Square")]
        let shrink = sample.member(tiny, leaf, "Tiny::shrink", .function)
        sample.refer(shrink, sample.named("Base::size"))
        #expect(FieldLeakRule().check(sample.context()).isEmpty)
    }
}
