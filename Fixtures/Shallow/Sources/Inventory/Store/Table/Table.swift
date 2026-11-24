struct Table {
    private var keys: [UInt32] = []
    private var values: [UInt32] = []

    var count: Int { keys.count }

    mutating func put(_ key: UInt32, _ value: UInt32) {
        if let at = find(key) {
            values[at] = value
        } else {
            keys.append(key)
            values.append(value)
        }
    }

    func find(_ key: UInt32) -> Int? {
        keys.firstIndex(of: key)
    }

    func value(at index: Int) -> UInt32 {
        values[index]
    }

    mutating func take(_ index: Int) -> UInt32 {
        keys.remove(at: index)
        return values.remove(at: index)
    }
}
