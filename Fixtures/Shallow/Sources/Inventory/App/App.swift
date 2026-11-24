public func run(_ pairs: [(UInt32, UInt32)]) -> UInt64 {
    var store = Store(limit: 8)
    for (key, value) in pairs where store.isFull || !store.insert(key, value) {
        _ = store.remove(key)
    }
    let kept = pairs.filter { store.contains($0.0) }.count
    let found = pairs.compactMap { store.get($0.0) }.count
    let rest = kept + found + store.room + store.limit
    return store.total + UInt64(store.largest ?? 0) + UInt64(rest)
}
