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
