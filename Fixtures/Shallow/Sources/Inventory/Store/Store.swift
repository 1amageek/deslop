public struct Store {
    private var table: Table
    private var capacity: Int

    public init(limit: Int) {
        table = Table()
        capacity = limit
    }

    public var limit: Int { capacity }

    public mutating func insert(_ key: UInt32, _ value: UInt32) -> Bool {
        if table.count >= capacity { return false }
        table.put(key, value)
        return true
    }

    public func get(_ key: UInt32) -> UInt32? {
        table.find(key).map { table.value(at: $0) }
    }

    public mutating func remove(_ key: UInt32) -> UInt32? {
        guard let at = table.find(key) else { return nil }
        return table.take(at)
    }

    public func contains(_ key: UInt32) -> Bool {
        table.find(key) != nil
    }

    public var room: Int { capacity - table.count }

    public var isFull: Bool { room == 0 }

    public var total: UInt64 {
        (0..<table.count).reduce(0) { $0 + UInt64(table.value(at: $1)) }
    }

    public var largest: UInt32? {
        (0..<table.count).map { table.value(at: $0) }.max()
    }
}
