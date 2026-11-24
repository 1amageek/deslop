import DeslopModel

/// A place in a workspace file: where an item is defined, or where the
/// index names something, by the position of its name.
struct Site: Hashable, Sendable {
    let file: FileID
    let position: SourcePosition
}
