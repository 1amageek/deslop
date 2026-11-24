public struct RunQueue {
    private var items: [UInt32]
    private var head: Int
    private var limit: Int

    public init(limit: Int) {
        items = []
        head = 0
        self.limit = limit
    }

    public var isFull: Bool { items.count - head >= limit }

    public mutating func admit(_ task: UInt32) -> Bool {
        if isFull { return false }
        items.append(task)
        return true
    }

    public mutating func next() -> UInt32? {
        guard let task = items.dropFirst(head).first else { return nil }
        head += 1
        return task
    }

    public var backlog: Int { items.count - head }

    public var drained: Bool { head == items.count }
}
