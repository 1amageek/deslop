public func backlog(_ queue: RunQueue) -> Int {
    queue.count
}

public func drained(_ queue: RunQueue) -> Bool {
    queue.count == 0
}
