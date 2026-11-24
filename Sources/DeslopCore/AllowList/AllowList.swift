/// Plain-text allowlist for existing architectural debt: one `<lint> <key>`
/// per line, sorted. Fixing an allowed entry never fails the check.
public struct AllowList: Equatable, Sendable {
    private struct Entry: Hashable, Sendable {
        let lint: Lint
        let key: String
    }

    private var entries: Set<Entry>

    public init(diagnostics: [Diagnostic]) {
        entries = Set(diagnostics.map { Entry(lint: $0.lint, key: $0.key) })
    }

    public init(parsing text: String) throws(AllowListError) {
        var entries: Set<Entry> = []
        // `\r\n` is one `Character`, and a line break of its own.
        for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let trimmed = line.trimmingWhitespace()
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let space = trimmed.firstIndex(of: " "),
                  let lint = Lint(name: String(trimmed[..<space])) else {
                throw .invalidEntry(line: index + 1)
            }
            let key = trimmed[trimmed.index(after: space)...].trimmingWhitespace()
            guard !key.isEmpty else { throw .invalidEntry(line: index + 1) }
            entries.insert(Entry(lint: lint, key: key))
        }
        self.entries = entries
    }

    /// The allowlist as its file holds it, headed by how it is used; `tool`
    /// is the command that reads it.
    public func text(tool: String) -> String {
        var out = "# Existing architectural debt suppressed by `\(tool) --allow`.\n"
            + "# Fixing an entry here never fails CI; new issues not listed here fail.\n"
        let sorted = entries.sorted { a, b in
            a.lint != b.lint ? a.lint < b.lint : Text.precedes(a.key, b.key)
        }
        for entry in sorted {
            out += "\(entry.lint.name) \(entry.key)\n"
        }
        return out
    }

    public var count: Int { entries.count }

    /// The entries of both.
    public func union(_ other: AllowList) -> AllowList {
        var joined = self
        joined.entries.formUnion(other.entries)
        return joined
    }

    /// The entries that allow at least one of `diagnostics`.
    public func covering(_ diagnostics: [Diagnostic]) -> AllowList {
        var kept = self
        kept.entries = entries.filter { entry in diagnostics.contains { covers(entry, $0) } }
        return kept
    }

    public func allows(_ diagnostic: Diagnostic) -> Bool {
        entries.contains { covers($0, diagnostic) }
    }

    /// Allowed entries that are no longer present in `diagnostics`.
    public func fixedCount(_ diagnostics: [Diagnostic]) -> Int {
        entries.filter { entry in !diagnostics.contains { covers(entry, $0) } }.count
    }

    /// Whether `entry` allows `diagnostic`. Shrinking an allowed circle is an
    /// improvement, never a new error, so an entry allows every tangle or
    /// module cycle whose members are among its own.
    private func covers(_ entry: Entry, _ diagnostic: Diagnostic) -> Bool {
        guard diagnostic.lint == entry.lint else { return false }
        if diagnostic.key == entry.key { return true }
        guard entry.lint == .tangle || entry.lint == .moduleCycle else { return false }
        let allowed = Set(AllowList.members(entry.key))
        return AllowList.members(diagnostic.key).allSatisfy(allowed.contains)
    }

    /// The members a circle's key lists. A member's own commas are inside
    /// brackets, as in `<(A, B) as Trait>::run`, and split nothing. A bracket
    /// that is never closed or never opened, as in the operator `<(_:_:)`,
    /// is a character of a name and brackets nothing.
    static func members(_ key: String) -> [String] {
        let characters = Array(key)
        let pairs: [Character: Character] = ["<": ">", "(": ")", "[": "]"]
        var open: [(character: Character, at: Int)] = []
        var matched: Set<Int> = []
        for (at, character) in characters.enumerated() {
            if pairs[character] != nil {
                open.append((character, at))
            } else if let opening = open.lastIndex(where: { pairs[$0.character] == character }) {
                matched.insert(open[opening].at)
                matched.insert(at)
                open.removeSubrange(opening...)
            }
        }
        var members: [String] = []
        var depth = 0
        var current = ""
        for (at, character) in characters.enumerated() {
            if matched.contains(at) {
                depth += pairs[character] != nil ? 1 : -1
            } else if character == ",", depth == 0 {
                members.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        members.append(current)
        return members
    }
}

extension StringProtocol {
    fileprivate func trimmingWhitespace() -> String {
        let start = firstIndex { !$0.isWhitespace } ?? endIndex
        let end = lastIndex { !$0.isWhitespace }.map { index(after: $0) } ?? start
        return String(self[start..<end])
    }
}
