/// What code does with a field, or with what an accessor lends, at the
/// place that names it.
enum Access: Sendable, Equatable {
    /// Uses its value: `queue.head + 1`, `return queue.head`, `f(queue.head)`.
    case copy
    /// Lends a view of it to read: `queue.name.utf8`.
    case borrow
    /// Reaches a member of it: `queue.items.count`, `queue.items.first()`.
    case call
    /// Writes it, passes it `inout`, or subscripts it: `queue.head = 0`,
    /// `swap(&queue.head, &other)`, `queue.items[0]`.
    case reach
}
