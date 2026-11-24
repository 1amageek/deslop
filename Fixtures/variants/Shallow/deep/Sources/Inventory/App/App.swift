public func run(_ pairs: [(UInt32, UInt32)]) -> UInt64 {
    var store = Store(limit: 8)
    store.load(pairs)
    return store.summary
}
