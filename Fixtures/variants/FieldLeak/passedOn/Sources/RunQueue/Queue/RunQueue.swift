public struct RunQueue {
    private var ring: Ring
    private var limit: Int

    public init(limit: Int) {
        ring = Ring()
        self.limit = limit
    }

    public var isFull: Bool { ring.count >= limit }

    mutating func push(_ task: UInt32) {
        ring.push(task)
    }

    mutating func pop() -> UInt32? {
        ring.pop()
    }

    var count: Int { ring.count }
}
