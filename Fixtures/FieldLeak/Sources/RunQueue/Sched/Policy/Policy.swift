public func admit(_ queue: inout RunQueue, _ task: UInt32) -> Bool {
    if queue.isFull { return false }
    queue.items.append(task)
    return true
}

public func next(_ queue: inout RunQueue) -> UInt32? {
    guard let task = queue.items.dropFirst(queue.head).first else { return nil }
    queue.head += 1
    return task
}
