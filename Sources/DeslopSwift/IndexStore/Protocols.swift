/// What the index says of protocols, the workspace's and those of the
/// modules it imports: the names of each one's requirements, and the
/// protocols each one refines.
struct Protocols: Sendable {
    /// How a function meets the requirements of protocols.
    enum Match: Equatable, Sendable {
        /// A requirement has its name and its signature.
        case signature
        /// A requirement has its name only.
        case name
        case none
    }

    /// By protocol USR, the requirements: by name (`init(from:)`,
    /// `==(_:_:)`), the signatures their USRs write, `nil` where a USR
    /// writes none this reads.
    private var requirements: [String: [String: Set<String?>]] = [:]
    /// By protocol USR, the protocols it refines: `Hashable` refines `Equatable`.
    private var refines: [String: Set<String>] = [:]

    /// Adds what `occurrences` say: a requirement is defined as a child of a
    /// protocol; a refinement names a protocol as the base of another.
    mutating func add(_ occurrences: [IndexOccurrence]) {
        for occurrence in occurrences {
            if occurrence.roles.contains(.definition) {
                for relation in occurrence.relations
                where relation.roles.contains(.childOf) && relation.symbol.kind == .protocol {
                    let name = occurrence.symbol.name
                    requirements[relation.symbol.usr, default: [:]][name, default: []]
                        .insert(Protocols.signature(usr: occurrence.symbol.usr, name: name))
                }
            }
            guard occurrence.symbol.kind == .protocol else { continue }
            for relation in occurrence.relations
            where relation.roles.contains(.baseOf) && relation.symbol.kind == .protocol {
                refines[relation.symbol.usr, default: []].insert(occurrence.symbol.usr)
            }
        }
    }

    /// How a function of `name` and `signature` meets the requirements of
    /// `protocols` and of the protocols they refine.
    func match(_ name: String, signature: String?, ofAny protocols: Set<String>) -> Match {
        var named = false
        for found in closure(protocols) {
            guard let signatures = requirements[found]?[name] else { continue }
            if let signature, signatures.contains(signature) { return .signature }
            named = true
        }
        return named ? .name : .none
    }

    /// The signature a USR writes after a function's base name: `SiyF` of
    /// `s:5Proto5StepsP1aSiyF` for `a()`. A conformer's witness writes the
    /// same, unless the requirement's names `Self` or an associated type.
    /// `nil` when the USR does not write the base name as an identifier, as
    /// for initializers and operators.
    static func signature(usr: String, name: String) -> String? {
        let base = name.prefix { $0 != "(" }
        guard !base.isEmpty, base.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        let token = "\(base.utf8.count)\(base)"
        guard let found = usr.ranges(of: token).last else { return nil }
        return String(usr[found.upperBound...])
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
