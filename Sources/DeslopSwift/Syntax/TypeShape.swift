import SwiftSyntax

/// What a type written in a declaration is, as far as whether it is a
/// value type: an array, dictionary or literal type is one; an optional or
/// a tuple is one when what it holds is; a named type is one when the index
/// says the name at `position` is a struct or an enum.
indirect enum TypeShape: Sendable, Equatable {
    case value
    case named(SourcePosition)
    case optional(TypeShape)
    case tuple([TypeShape])
    /// An existential, an opaque type, a function: not known to be a value.
    case unknown

    /// The shape of `type`, its names placed by `position`.
    static func of(_ type: TypeSyntax, position: (TokenSyntax) -> SourcePosition) -> TypeShape {
        if type.is(ArrayTypeSyntax.self) || type.is(DictionaryTypeSyntax.self) {
            return .value
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return .optional(of(optional.wrappedType, position: position))
        }
        if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return .optional(of(unwrapped.wrappedType, position: position))
        }
        if let tuple = type.as(TupleTypeSyntax.self) {
            let elements = tuple.elements.map { of($0.type, position: position) }
            return elements.count == 1 ? elements[0] : .tuple(elements)
        }
        if let named = type.as(IdentifierTypeSyntax.self) {
            return .named(position(named.name))
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return .named(position(member.name))
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return of(attributed.baseType, position: position)
        }
        return .unknown
    }

    /// Whether it is a value type, `isValue` telling a named type's.
    func isValue(_ isValue: (SourcePosition) -> Bool) -> Bool {
        switch self {
        case .value: true
        case .named(let position): isValue(position)
        case .optional(let wrapped): wrapped.isValue(isValue)
        case .tuple(let elements): elements.allSatisfy { $0.isValue(isValue) }
        case .unknown: false
        }
    }
}
