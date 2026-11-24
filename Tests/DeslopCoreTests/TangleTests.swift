import DeslopModel
import Testing
@testable import DeslopCore

@Suite("tangle")
struct TangleTests {
    private func keys(_ sample: Sample) -> [String] {
        TangleRule().check(sample.context()).map(\.key)
    }

    @Test("two things in a circle are reported when their code is in two modules")
    func acrossModules() {
        var sample = Sample()
        let (kernel, timers) = (sample.module("kernel"), sample.module("kernel::timers"))
        let tasks = sample.item(kernel, "Tasks", .type)
        let timer = sample.item(timers, "Timers", .type)
        let spawn = sample.member(tasks, kernel, "Tasks::spawn", .function)
        let fire = sample.member(timer, timers, "Timers::fire", .function)
        sample.refer(spawn, timer)
        sample.refer(fire, tasks)
        #expect(keys(sample) == ["p::kernel::Tasks,p::kernel::timers::Timers"])
    }

    @Test("a circle in one module is reported only when it is too big to hold in mind")
    func tooBigInOneModule() {
        var sample = Sample()
        let module = sample.module("ring")
        func ring(_ size: Int) {
            let things = (0..<size).map { sample.item(module, "T\(size)x\($0)", .type) }
            for index in 0..<size {
                sample.refer(things[index], things[(index + 1) % size])
            }
        }
        ring(Text.heldInMind)
        #expect(keys(sample).isEmpty)
        ring(Text.heldInMind + 1)
        #expect(keys(sample).count == 1)
    }

    @Test("the picture is the shortest circle through the cheapest tie")
    func pictureIsShortestCircle() {
        var sample = Sample()
        let (aModule, bModule) = (sample.module("a"), sample.module("b"))
        let a = sample.item(aModule, "A", .type)
        let aX = sample.member(a, aModule, "A::x", .function)
        let b = sample.item(bModule, "B", .type)
        let bRun = sample.member(b, bModule, "B::run", .function)
        let c = sample.item(bModule, "C", .type)
        sample.refer(a, b)
        sample.refer(bRun, c)
        sample.refer(c, a)
        sample.refer(bRun, a)
        sample.refer(bRun, aX)
        let diagnostics = TangleRule().check(sample.context())
        guard case .circle(let steps, let rest) = diagnostics[0].picture else {
            Issue.record("a tangle draws a circle")
            return
        }
        #expect(steps.map { [$0.member, $0.uses] } == [["p::a::A", "A uses B"], ["p::b::B", "B::run uses A::{self, x}"]])
        #expect(rest == "not drawn: 1 more thing, 2 more ties")
    }

    @Test("an impl block written elsewhere ties its type from there")
    func implElsewhere() {
        var sample = Sample()
        let (scheduling, elsewhere) = (sample.module("scheduling"), sample.module("elsewhere"))
        let tasks = sample.item(scheduling, "Tasks", .type)
        let timers = sample.item(scheduling, "Timers", .type)
        let spawn = sample.member(tasks, scheduling, "Tasks::spawn", .function)
        let fire = sample.member(timers, elsewhere, "Timers::fire", .function)
        sample.refer(spawn, timers)
        sample.refer(fire, tasks)
        let diagnostics = TangleRule().check(sample.context())
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message == "2 things know each other in a circle, across 2 modules")
        #expect(diagnostics[0].notes[1] == "written in: p::elsewhere, p::scheduling")
    }

    @Test("a tie written in two modules is shown in both")
    func tieInTwoModules() {
        var sample = Sample()
        let (tail, writer) = (sample.module("tail"), sample.module("writer"))
        let walTail = sample.item(tail, "WalTail", .type)
        let scanned = sample.item(tail, "Scanned", .type)
        let scanBytes = sample.member(walTail, tail, "WalTail::scan_bytes", .function)
        let scanFile = sample.member(walTail, writer, "WalTail::scan_file", .function)
        let records = sample.member(scanned, tail, "Scanned::records", .field)
        sample.refer(scanBytes, scanned)
        sample.refer(scanFile, records)
        sample.refer(scanned, walTail)
        let notes = TangleRule().check(sample.context())[0].notes
        #expect(notes[1] == "written in: p::tail, p::writer")
        #expect(notes[3].hasSuffix("; also at src/writer.rs:2:1"), "\(notes[3])")
    }
}

@Suite("tangle of overloads")
struct TangleOverloadTests {
    @Test("two things of one name are two members of the circle drawn")
    func overloads() {
        var sample = Sample()
        let (a, b) = (sample.module("a"), sample.module("b"))
        let first = sample.item(a, "f", .function)
        let g = sample.item(b, "g", .function)
        let second = sample.item(a, "f", .function)
        sample.refer(first, g)
        sample.refer(g, second)
        sample.refer(second, first)
        let diagnostics = TangleRule().check(sample.context())
        guard case .circle(let steps, _) = diagnostics.first?.picture else {
            Issue.record("a tangle draws a circle")
            return
        }
        #expect(steps.count == 3)
        #expect(Set(steps.map(\.member)) == ["p::a::f", "p::b::g"])
    }
}
