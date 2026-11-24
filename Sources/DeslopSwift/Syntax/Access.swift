/// What code does with a field, or with what an accessor lends, at the
/// place that names it.
enum Access: Int, Sendable, Comparable {
    /// Uses its value: `queue.head + 1`, `return queue.head`, `f(queue.head)`.
    case copy
    /// Lends a view of it to read: `queue.name.utf8`.
    case borrow
    /// Reaches a member of it: `queue.items.count`, `queue.items.first()`.
    case call
    /// Subscripts it: `queue.items[0]`. A read of a value, unless the index
    /// marks a write; else it reaches into the field.
    case subscripted
    /// Writes it, or passes it `inout`: `queue.head = 0`, `swap(&queue.head, &other)`.
    case reach

    /// Least to most: what a place does at most, when it is used in more than one way.
    static func < (lhs: Access, rhs: Access) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
