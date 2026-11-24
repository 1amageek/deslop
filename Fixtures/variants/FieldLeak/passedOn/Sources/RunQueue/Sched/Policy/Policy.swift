public func admit(_ queue: inout RunQueue, _ task: UInt32) -> Bool {
    if queue.isFull { return false }
    queue.push(task)
    return true
}

public func next(_ queue: inout RunQueue) -> UInt32? {
    queue.pop()
}
