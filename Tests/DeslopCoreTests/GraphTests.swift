import DeslopModel
import Testing
@testable import DeslopCore

@Suite("Graph")
struct GraphTests {
    @Test("a method written anywhere is part of its type, and things that use each other are a tangle")
    func methodsBelongToTheirTypeAndCirclesAreTangles() {
        var sample = Sample()
        let (a, b) = (sample.module("a"), sample.module("b"))
        let tasks = sample.item(a, "Tasks", .type)
        let timers = sample.item(b, "Timers", .type)
        let fire = sample.member(timers, a, "Timers::fire", .function)
        let spawn = sample.member(tasks, a, "Tasks::spawn", .function)
        sample.refer(fire, tasks)
        sample.refer(spawn, timers)
        let graph = sample.graph
        let ofFire = graph.thing(of: fire)!
        #expect(graph.thing(ofFire).item == timers)
        #expect(graph.thing(ofFire).home == b)
        #expect(graph.tangleIDs.count == 1)
        #expect(graph.members(of: graph.tangleIDs[0]).count == 2)
    }

    @Test("a use of a wrapper is a use of what is behind it, and its own body is no use")
    func wrappersAreSeenThrough() {
        var sample = Sample()
        let (a, b) = (sample.module("a"), sample.module("b"))
        let queue = sample.item(a, "Queue", .type)
        let inner = sample.item(a, "Inner", .type)
        let items = sample.member(inner, a, "Inner::items", .field)
        let field = sample.member(queue, a, "Queue::inner", .field)
        let getter = sample.member(inner, a, "Inner::items", .function)
        let forwarder = sample.member(queue, a, "Queue::items", .function)
        sample.model.wrappers[getter] = .accessor(lent: [items], copied: [], toRead: true)
        sample.model.wrappers[forwarder] = .forwarder(target: getter, fields: [field])
        sample.refer(getter, items)
        sample.refer(forwarder, field)
        sample.refer(forwarder, getter)
        let report = sample.item(b, "report", .function)
        sample.refer(report, forwarder)
        let graph = sample.graph
        let used = graph.uses.map { [$0.item, $0.through] }
        #expect(used == [[field, forwarder], [items, forwarder]])
        let reporter = graph.thing(of: report)
        #expect(graph.uses.allSatisfy { $0.user == reporter })
    }

    @Test("strongly connected components find each circle and leave out the rest")
    func circles() {
        let edges = [[1], [2], [0, 3], [4], [3], []]
        #expect(StronglyConnectedComponents.circles(edges) == [[0, 1, 2], [3, 4]])
    }
}
