/// A place in a file where the index records a symbol.
struct IndexOccurrence: Sendable {
    /// A symbol the occurrence relates to, and how.
    struct Relation: Sendable {
        let roles: SymbolRoles
        let symbol: IndexSymbol
    }

    let symbol: IndexSymbol
    let roles: SymbolRoles
    /// 1-based.
    let line: Int
    /// 1-based, in UTF-8 bytes.
    let column: Int
    let relations: [Relation]

    /// The symbol of the first relation with `role`.
    func related(_ role: SymbolRoles) -> IndexSymbol? {
        relations.first { $0.roles.contains(role) }?.symbol
    }
}
