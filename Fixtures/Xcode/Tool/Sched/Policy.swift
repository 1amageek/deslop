func admit(_ queue: inout RunQueue, _ task: UInt32) -> Bool {
    if queue.isFull { return false }
    queue.items.append(task)
    return true
}
