public struct Job {
    public var id: UInt32
    public var asleep: Bool
}

public struct Tasks {
    private var list: [Job] = []

    public init() {}

    public mutating func spawn(_ id: UInt32, timers: inout Timers) {
        list.append(Job(id: id, asleep: true))
        timers.arm(id, at: 10)
    }

    public mutating func wake(_ id: UInt32) {
        for index in list.indices where list[index].id == id {
            list[index].asleep = false
        }
    }

    public var runnable: Int { list.filter { !$0.asleep }.count }
}

public struct Timers {
    private var due: [(id: UInt32, at: UInt64)] = []

    public init() {}

    public mutating func arm(_ id: UInt32, at: UInt64) {
        due.append((id, at))
    }

    public mutating func fire(_ now: UInt64, tasks: inout Tasks) {
        for entry in due where entry.at <= now {
            tasks.wake(entry.id)
        }
        due.removeAll { $0.at <= now }
    }
}
