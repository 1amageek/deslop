struct RunQueue {
    var items: [UInt32] = []
    var head: Int = 0
    private var limit: Int = 8

    var isFull: Bool { items.count - head >= limit }
}
