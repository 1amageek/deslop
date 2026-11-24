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

    /// The signature a USR writes after a function's base name, demangled:
    /// `(_: Swift.Int) -> Swift.Int` of `Lib.Machine.scaleMachine(_: Swift.Int) -> Swift.Int`,
    /// ` : Swift.Int` of a property. A conformer's witness writes the same,
    /// unless the requirement's names `Self` or an associated type. `nil`
    /// for an initializer or an operator, whose signature names the type it
    /// is written in or its operands, and where the runtime does not demangle
    /// the USR or the text does not write the name.
    static func signature(usr: String, name: String) -> String? {
        let base = name.prefix { $0 != "(" }
        guard !base.isEmpty, base != "init", base.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              let text = Demangled.text(ofUSR: usr) else { return nil }
        // The first place the text writes the name as a member, after the
        // context it is written in: what follows is the signature.
        var from = text.startIndex
        while let found = text.range(of: "." + base, range: from..<text.endIndex) {
            if found.upperBound < text.endIndex, "( <".contains(text[found.upperBound]) {
                return String(text[found.upperBound...])
            }
            from = found.upperBound
        }
        return nil
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
