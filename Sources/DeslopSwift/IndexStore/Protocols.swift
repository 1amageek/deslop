/// What the index says of protocols, the workspace's and those of the
/// modules it imports: the names of each one's requirements, and the
/// protocols each one refines.
struct Protocols: Sendable {
    /// By protocol USR, the names of its requirements: `init(from:)`, `==(_:_:)`.
    private var requirements: [String: Set<String>] = [:]
    /// By protocol USR, the protocols it refines: `Hashable` refines `Equatable`.
    private var refines: [String: Set<String>] = [:]

    /// Adds what `occurrences` say: a requirement is defined as a child of a
    /// protocol; a refinement names a protocol as the base of another.
    mutating func add(_ occurrences: [IndexOccurrence]) {
        for occurrence in occurrences {
            if occurrence.roles.contains(.definition) {
                for relation in occurrence.relations
                where relation.roles.contains(.childOf) && relation.symbol.kind == .protocol {
                    requirements[relation.symbol.usr, default: []].insert(occurrence.symbol.name)
                }
            }
            guard occurrence.symbol.kind == .protocol else { continue }
            for relation in occurrence.relations
            where relation.roles.contains(.baseOf) && relation.symbol.kind == .protocol {
                refines[relation.symbol.usr, default: []].insert(occurrence.symbol.usr)
            }
        }
    }

    /// Whether `name` is a requirement of one of `protocols`, or of a
    /// protocol they refine.
    func requires(_ name: String, ofAny protocols: Set<String>) -> Bool {
        closure(protocols).contains { requirements[$0]?.contains(name) == true }
    }

    /// `protocols` and every protocol they refine, through any number of steps.
    private func closure(_ protocols: Set<String>) -> Set<String> {
        var found: Set<String> = []
        var pending = Array(protocols)
        while let next = pending.popLast() {
            if found.insert(next).inserted {
                pending.append(contentsOf: refines[next] ?? [])
            }
        }
        return found
    }
}
