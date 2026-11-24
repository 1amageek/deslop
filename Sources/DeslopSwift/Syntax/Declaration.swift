import SwiftSyntax

/// A declaration of a source file, found at the position of its name.
struct Declaration {
    enum Kind: Equatable {
        case type
        case storedProperty
        case computedProperty
        case function
        case initializer
        case deinitializer
        case `subscript`
        case enumCase
    }

    let kind: Kind
    /// Declared `static` or `class`.
    let isStatic: Bool
    /// The type a property's initial value constructs, `Inner` for
    /// `Inner()`, when the index confirms that the name at `position` is a
    /// type; `position` is `nil` when the syntax alone says so, as `[Int]()` does.
    struct Constructed {
        let tokens: [String]
        let position: SourcePosition?
    }

    /// The tokens of a property's declared type, or of the type its literal
    /// initial value has; `nil` when neither is written.
    let declaredType: [String]?
    /// The type the property's initial value constructs, when no type is
    /// written and the value is no literal.
    var constructed: Constructed? = nil
    /// Whether its type is a value type, as far as the syntax says: the
    /// written type's shape, a literal's (a value), or the constructed type's.
    var shape: TypeShape = .unknown
    /// The internal names of a function's or subscript's parameters, in order.
    let parameters: [String]
    /// The tokens of what comes before the body: parameter and result types,
    /// or a property's type.
    let signature: [String]
    /// The statements of each body it has: a function's, or each accessor's.
    let bodies: [CodeBlockItemListSyntax]
    /// A property with a setter, or a body that assigns.
    let hasSetter: Bool
    /// What a reference inside it is held by, in UTF-8 offsets of the file.
    let range: Range<Int>
}
