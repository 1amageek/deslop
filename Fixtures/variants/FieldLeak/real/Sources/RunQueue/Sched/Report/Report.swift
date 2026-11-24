public func backlog(_ queue: RunQueue) -> Int {
    queue.backlog
}

public func drained(_ queue: RunQueue) -> Bool {
    queue.drained
}
