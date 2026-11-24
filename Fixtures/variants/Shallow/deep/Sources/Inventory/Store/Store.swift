public struct Store {
    private var table: Table
    private var capacity: Int

    public init(limit: Int) {
        table = Table()
        capacity = limit
    }

    public mutating func load(_ pairs: [(UInt32, UInt32)]) {
        for (key, value) in pairs where isFull || !insert(key, value) {
            _ = remove(key)
        }
    }

    public var summary: UInt64 {
        let kept = (0..<table.count).count
        return total + UInt64(largest ?? 0) + UInt64(kept + room + capacity)
    }

    mutating func insert(_ key: UInt32, _ value: UInt32) -> Bool {
        if table.count >= capacity { return false }
        table.put(key, value)
        return true
    }

    mutating func remove(_ key: UInt32) -> UInt32? {
        guard let at = table.find(key) else { return nil }
        return table.take(at)
    }

    var room: Int { capacity - table.count }

    var isFull: Bool { room == 0 }

    var total: UInt64 {
        (0..<table.count).reduce(0) { $0 + UInt64(table.value(at: $1)) }
    }

    var largest: UInt32? {
        (0..<table.count).map { table.value(at: $0) }.max()
    }
}
