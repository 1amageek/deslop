import DeslopModel

/// How reports write lists, counts and names.
public enum Text {
    /// What a reader can hold in mind at once: seven (Miller, "The Magical
    /// Number Seven, Plus or Minus Two", 1956). A note or a picture lists no
    /// more than this.
    public static let heldInMind = 7

    /// Whether `a` comes before `b`, byte by byte, as Rust orders strings, so
    /// that every frontend's names sort the same way.
    public static func precedes(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    public static func sorted(_ names: [String]) -> [String] {
        names.sorted(by: precedes)
    }

    /// `a, b, c, +2 more`: at most seven of `names`.
    public static func listed(_ names: [String]) -> String {
        let shown = names.prefix(heldInMind).joined(separator: ", ")
        let more = names.count - heldInMind
        return more > 0 ? "\(shown), +\(more) more" : shown
    }

    /// `1 module`, `2 modules`.
    public static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    /// `file:line:1`, the shape compilers write, so terminals and editors link it.
    public static func clickable(_ location: Location) -> String {
        "\(location.file):\(location.line):1"
    }

    /// `<Ready as Display>`: a name with generic arguments left out.
    public static func withoutGenerics(_ name: String) -> String {
        var out = ""
        var depth = 0
        for character in name {
            switch character {
            case "<" where depth > 0 || out.last.map(isWordCharacter) == true:
                depth += 1
            case ">" where depth > 0:
                depth -= 1
            case _ where depth > 0:
                continue
            default:
                out.append(character)
            }
        }
        return out
    }

    /// `Stream::{self, new}, LIMIT`: `names`, with those under one name
    /// written once, as a Rust `use` declaration writes them; `separator`
    /// joins a name to the names inside it.
    public static func grouped(_ names: [String], separator: String) -> String {
        var groups: [(head: String, tails: [String])] = []
        for name in names {
            let head: String
            let tail: String
            if let range = name.firstRange(of: separator) {
                head = String(name[..<range.lowerBound])
                tail = String(name[range.upperBound...])
            } else {
                head = name
                tail = "self"
            }
            if let at = groups.firstIndex(where: { $0.head == head }) {
                groups[at].tails.append(tail)
            } else {
                groups.append((head, [tail]))
            }
        }
        let written = groups.map { head, tails in
            if tails.count == 1 {
                tails[0] == "self" ? head : "\(head)\(separator)\(tails[0])"
            } else {
                "\(head)\(separator){\(listed(tails))}"
            }
        }
        return listed(written)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}

extension Text {
    /// `package::module::Ready`: where a thing is defined, and its name there.
    static func fullName(_ thing: ThingID, _ context: LintContext) -> String {
        let found = context.graph.thing(thing)
        return context.hierarchy.display(found.home) + context.model.language.pathSeparator
            + name(found.item, in: context.model)
    }

    /// An item's name, without generic arguments.
    static func name(_ item: ItemID, in model: Model) -> String {
        withoutGenerics(model.item(item).name)
    }

    /// The names of `items`, in the order of their identifiers.
    static func names(_ items: Set<ItemID>, in model: Model) -> [String] {
        items.sorted().map { name($0, in: model) }
    }

    /// The line a reference is written on.
    static func site(_ reference: Reference, in model: Model) -> Location {
        Location(file: model.file(reference.file).path, line: reference.line)
    }

    /// The first line of `module`'s primary non-test file, if it has one: the
    /// file of lowest rank, then the first by path.
    static func moduleLocation(_ module: NodeID, in model: Model) -> Location? {
        let candidates = model.files.filter { !$0.test && $0.module == module }
        let primary = candidates.min { a, b in
            a.rank != b.rank ? a.rank < b.rank : precedes(a.path, b.path)
        }
        return primary.map { Location(file: $0.path, line: 1) }
    }
}
