import DeslopModel
import Testing
@testable import DeslopCore

@Suite("module-cycle")
struct ModuleCycleTests {
    private func keys(_ sample: Sample) -> [String] {
        ModuleCycleRule().check(sample.context()).map(\.key)
    }

    @Test("siblings that use each other are a circle though no two things are")
    func siblingsInACircle() {
        var sample = Sample()
        let (socket, kinds) = (sample.module("socket"), sample.module("kinds"))
        let open = sample.item(socket, "open", .function)
        let limit = sample.item(socket, "LIMIT", .constant)
        let stream = sample.item(kinds, "Stream", .type)
        let checkLimit = sample.item(kinds, "fits", .function)
        sample.refer(open, stream)
        #expect(keys(sample).isEmpty)
        sample.refer(checkLimit, limit)
        let diagnostics = ModuleCycleRule().check(sample.context())
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].key == "p::kinds,p::socket")
        #expect(diagnostics[0].message == "2 modules in `p` use each other in a circle")
        #expect(diagnostics[0].notes == [
            "members: kinds, socket",
            "src/kinds.rs:2:1: `kinds` uses `socket` by 1 item: LIMIT",
            "src/socket.rs:1:1: `socket` uses `kinds` by 1 item: Stream",
        ])
        #expect(diagnostics[0].picture == .circle(
            steps: [
                Step(member: "kinds", site: Location(file: "src/kinds.rs", line: 2), uses: "fits uses LIMIT"),
                Step(member: "socket", site: Location(file: "src/socket.rs", line: 1), uses: "open uses Stream"),
            ],
            rest: nil
        ))
    }

    @Test("a circle is between the children of the module that holds it")
    func betweenChildren() {
        var sample = Sample()
        let (epoll, address) = (sample.module("kinds::epoll"), sample.module("socket::address"))
        let wait = sample.item(epoll, "wait", .function)
        let parse = sample.item(address, "parse", .function)
        sample.refer(wait, parse)
        sample.refer(parse, wait)
        #expect(keys(sample) == ["p::kinds,p::socket"])
    }

    @Test("a module and what is inside it make no circle")
    func moduleAndInside() {
        var sample = Sample()
        let (kinds, epoll) = (sample.module("kinds"), sample.module("kinds::epoll"))
        let kind = sample.item(kinds, "Kind", .type)
        let wait = sample.item(epoll, "wait", .function)
        let poll = sample.item(kinds, "poll", .function)
        sample.refer(wait, kind)
        sample.refer(poll, wait)
        #expect(keys(sample).isEmpty)
    }

    @Test("a method counts where it is written")
    func methodCountsWhereWritten() {
        var sample = Sample()
        let (tasks, timers) = (sample.module("tasks"), sample.module("timers"))
        let task = sample.item(tasks, "Tasks", .type)
        let timer = sample.item(timers, "Timers", .type)
        let fire = sample.member(timer, timers, "Timers::fire", .function)
        sample.refer(fire, task)
        let spawnInTimers = sample.member(task, timers, "Tasks::spawn", .function)
        sample.refer(spawnInTimers, timer)
        #expect(keys(sample).isEmpty)
        let spawnInTasks = sample.member(task, tasks, "Tasks::spawn", .function)
        sample.refer(spawnInTasks, timer)
        #expect(keys(sample) == ["p::tasks,p::timers"])
    }
}
