/// A symbol of the index.
struct IndexSymbol: Sendable, Hashable {
    /// libIndexStore's `indexstore_symbol_kind_t`.
    enum Kind: Int, Sendable {
        case unknown = 0, module = 1, namespace = 2, namespaceAlias = 3, macro = 4
        case `enum` = 5, `struct` = 6, `class` = 7, `protocol` = 8, `extension` = 9, union = 10, typeAlias = 11
        case function = 12, variable = 13, field = 14, enumConstant = 15
        case instanceMethod = 16, classMethod = 17, staticMethod = 18
        case instanceProperty = 19, classProperty = 20, staticProperty = 21
        case constructor = 22, destructor = 23, conversionFunction = 24, parameter = 25
        case using = 26, concept = 27, commentTag = 1000
    }

    /// libIndexStore's `indexstore_symbol_subkind_t`, as far as this reads it.
    enum Subkind {
        static let accessorGetter = 3
        static let accessorSetter = 4
        static let swiftAccessorWillSet = 1000
        static let swiftAccessorDidSet = 1001
        static let swiftAccessorAddressor = 1002
        static let swiftAccessorMutableAddressor = 1003
        static let swiftSubscript = 1011
        static let swiftAssociatedType = 1012
        static let swiftGenericTypeParameter = 1013
        /// Subkinds from here up to `swiftAccessorMutate` are accessors.
        static let swiftAccessorRead = 1014
        static let swiftAccessorMutate = 1018
    }

    /// libIndexStore's `indexstore_symbol_property_t`, as far as this reads it.
    enum Property {
        static let local: UInt64 = 1 << 7
    }

    let usr: String
    let name: String
    let kind: Kind
    let subkind: Int
    let properties: UInt64

    var isLocal: Bool { properties & Property.local != 0 }

    var isAccessor: Bool {
        subkind == Subkind.accessorGetter || subkind == Subkind.accessorSetter
            || subkind == Subkind.swiftAccessorWillSet || subkind == Subkind.swiftAccessorDidSet
            || (Subkind.swiftAccessorRead...Subkind.swiftAccessorMutate).contains(subkind)
            || subkind == Subkind.swiftAccessorAddressor || subkind == Subkind.swiftAccessorMutableAddressor
    }
}
