public func admit(_ queue: inout RunQueue, _ task: UInt32) -> Bool {
    queue.admit(task)
}

public func next(_ queue: inout RunQueue) -> UInt32? {
    queue.next()
}
