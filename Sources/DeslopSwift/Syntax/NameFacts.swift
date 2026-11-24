/// What the index says of names the syntax cannot tell apart, by where
/// they are written in a file.
struct NameFacts {
    /// Whether the member named there is a stored field, through which a
    /// place goes on: `queue.inner.items`.
    let isField: (SourcePosition) -> Bool
    /// What the signature of what the index names there declares of key
    /// paths: of a function called there, whether it takes a writable one,
    /// which it may write through: `write(&q, \.items)`. `nil` where the
    /// index names nothing, as at a local closure.
    let keyPathSignature: (SourcePosition) -> KeyPathSignature?
    /// What the code that uses the property or function the workspace
    /// defines or names there does with a key path it holds or returns, at
    /// most: `copy` when its signature declares no writable key path. `nil`
    /// where the index names none, as for a local.
    let keyPathFlow: (SourcePosition) -> Access?
}
