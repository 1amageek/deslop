public struct RunQueue {
    var items: [UInt32]
    var head: Int
    private var limit: Int

    public init(limit: Int) {
        items = []
        head = 0
        self.limit = limit
    }

    public var isFull: Bool { items.count - head >= limit }
}
