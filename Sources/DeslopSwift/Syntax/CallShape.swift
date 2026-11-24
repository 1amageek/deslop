/// The one call a function's body makes, when making it is all the body
/// does: `inner.push(item)`, `self.table.count`, `helper(key, value)`.
struct CallShape: Sendable, Equatable {
    /// What the call is made on.
    enum Base: Sendable, Equatable {
        /// Nothing is written before the callee's name: a free function, or a
        /// method of `self`.
        case unwritten
        /// `self.callee(...)`, `self.field.callee(...)`.
        case selfValue
        /// `field.callee(...)`: the path starts at a member of `self`.
        case implicitSelf
        /// `parameter.callee(...)`.
        case parameter(String)
    }

    let base: Base
    /// The names on the path between the base and the callee, which the
    /// index resolves; for `.implicitSelf`, the first is the member of `self`.
    let path: [SourcePosition]
    let callee: SourcePosition
    /// Each argument, as the name of what it passes when that is a bare name.
    let arguments: [String?]
    /// A call with arguments, rather than a property read: `f()` but not `x.count`.
    let isCall: Bool
}
