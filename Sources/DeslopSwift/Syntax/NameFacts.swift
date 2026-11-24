/// What the index says of names the syntax cannot tell apart, by where
/// they are written in a file.
struct NameFacts {
    /// Whether the member named there is a stored field, through which a
    /// place goes on: `queue.inner.items`.
    let isField: (SourcePosition) -> Bool
    /// Whether the function called there takes a writable key path, which it
    /// may write through: `write(&q, \.items)`.
    let takesWritableKeyPath: (SourcePosition) -> Bool
}
