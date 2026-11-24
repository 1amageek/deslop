public struct RunQueue {
    private var storage: [UInt32]
    private var cursor: Int
    private var limit: Int

    public init(limit: Int) {
        storage = []
        cursor = 0
        self.limit = limit
    }

    var items: [UInt32] {
        get { storage }
        set { storage = newValue }
    }

    var head: Int {
        get { cursor }
        set { cursor = newValue }
    }

    public var isFull: Bool { storage.count - cursor >= limit }
}
