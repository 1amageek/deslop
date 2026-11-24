/// What an occurrence of a symbol does, and how it relates to others, as
/// libIndexStore's `indexstore_symbol_role_t` writes it.
struct SymbolRoles: OptionSet, Sendable, Hashable {
    let rawValue: UInt64

    static let declaration = SymbolRoles(rawValue: 1 << 0)
    static let definition = SymbolRoles(rawValue: 1 << 1)
    static let reference = SymbolRoles(rawValue: 1 << 2)
    static let read = SymbolRoles(rawValue: 1 << 3)
    static let write = SymbolRoles(rawValue: 1 << 4)
    static let call = SymbolRoles(rawValue: 1 << 5)
    static let dynamic = SymbolRoles(rawValue: 1 << 6)
    static let implicit = SymbolRoles(rawValue: 1 << 8)
    static let childOf = SymbolRoles(rawValue: 1 << 9)
    static let baseOf = SymbolRoles(rawValue: 1 << 10)
    static let overrideOf = SymbolRoles(rawValue: 1 << 11)
    static let receivedBy = SymbolRoles(rawValue: 1 << 12)
    static let calledBy = SymbolRoles(rawValue: 1 << 13)
    static let extendedBy = SymbolRoles(rawValue: 1 << 14)
    static let accessorOf = SymbolRoles(rawValue: 1 << 15)
    static let containedBy = SymbolRoles(rawValue: 1 << 16)
}
