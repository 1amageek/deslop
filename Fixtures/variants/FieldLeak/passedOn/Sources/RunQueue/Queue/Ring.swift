struct Ring {
    private var slots: [UInt32] = []
    private var head = 0

    mutating func push(_ task: UInt32) {
        slots.append(task)
    }

    mutating func pop() -> UInt32? {
        guard let task = slots.dropFirst(head).first else { return nil }
        head += 1
        return task
    }

    var count: Int { slots.count - head }
}
