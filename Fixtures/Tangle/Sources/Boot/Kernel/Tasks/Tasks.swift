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
