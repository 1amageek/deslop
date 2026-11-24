public func backlog(_ queue: RunQueue) -> Int {
    queue.items.count - queue.head
}

public func drained(_ queue: RunQueue) -> Bool {
    queue.head == queue.items.count
}
