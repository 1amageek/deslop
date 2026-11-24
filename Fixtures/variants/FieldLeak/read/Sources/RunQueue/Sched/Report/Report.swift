public func backlog(_ queue: RunQueue) -> Int {
    queue.backlog
}

public func position(_ queue: RunQueue) -> String {
    let at = queue.head
    return "at \(at), \(queue.head.description)"
}
