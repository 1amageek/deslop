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
