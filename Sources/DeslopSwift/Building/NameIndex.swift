import DeslopModel

/// What the index says of the names of the workspace's files, for their
/// syntax to read: which members are fields, what the signatures of what
/// code calls declare of key paths, and what the code that uses a property
/// or function does with a key path it holds or returns, followed across
/// files from each place that names it.
final class NameIndex {
    private let items: [Item]
    private let usrOfItem: [ItemID: String]
    private let itemAtSite: [Site: ItemID]
    private let namedAt: [Site: [ItemID]]
    private let symbolsAt: [Site: [String]]
    /// By USR, its signature, once read.
    private var signatureOfUSR: [String: Signature] = [:]
    /// By item, the places that name it: where its value is used, or set.
    private let usesOfItem: [ItemID: [Site]]
    private let syntaxOfFile: [FileID: SourceSyntax]
    /// By item, what the code that uses it does with its key path, once known.
    private var flows: [ItemID: Access] = [:]
    /// The items whose flow is being found, which a use may lead back to.
    private var finding: Set<ItemID> = []
    /// Whether a flow being found met one still being found, so that it is
    /// final only once the first of them is.
    private var metUnfinished = false

    init(
        items: [Item],
        usrOfItem: [ItemID: String],
        itemAtSite: [Site: ItemID],
        namedAt: [Site: [ItemID]],
        symbolsAt: [Site: [String]],
        usesOfItem: [ItemID: [Site]],
        syntaxOfFile: [FileID: SourceSyntax]
    ) {
        self.items = items
        self.usrOfItem = usrOfItem
        self.itemAtSite = itemAtSite
        self.namedAt = namedAt
        self.symbolsAt = symbolsAt
        self.usesOfItem = usesOfItem
        self.syntaxOfFile = syntaxOfFile
    }

    /// What the index says of the names of `file`.
    func facts(_ file: FileID) -> NameFacts {
        NameFacts(
            isField: { [self] position in
                (namedAt[Site(file: file, position: position)] ?? []).contains { items[$0.index].kind == .field }
            },
            signatures: { [self] position in
                symbolsAt[Site(file: file, position: position)].map { $0.map(signature) }
            },
            keyPathFlow: { [self] position in
                let site = Site(file: file, position: position)
                let named = itemAtSite[site].map { [$0] } ?? namedAt[site] ?? []
                guard !named.isEmpty else { return nil }
                return named.map(flow).max()
            }
        )
    }

    private func signature(of usr: String) -> Signature {
        if let known = signatureOfUSR[usr] { return known }
        let read = Signature(usr: usr)
        signatureOfUSR[usr] = read
        return read
    }

    /// What the code that uses `item` does with a key path it holds or
    /// returns, at most. A use that leads back to an item whose flow is being
    /// found adds nothing to it: the least of what the uses do is found.
    private func flow(of item: ItemID) -> Access {
        if let known = flows[item] { return known }
        if finding.contains(item) {
            metUnfinished = true
            return .copy
        }
        guard let usr = usrOfItem[item], signature(of: usr).keyPaths != .readOnly else {
            flows[item] = .copy
            return .copy
        }
        finding.insert(item)
        let outerMet = metUnfinished
        metUnfinished = false
        var most = Access.copy
        for site in usesOfItem[item] ?? [] where most < .reach {
            guard let syntax = syntaxOfFile[site.file] else {
                most = .reach
                break
            }
            most = max(most, syntax.keyPathUse(at: site.position, facts: facts(site.file)))
        }
        finding.remove(item)
        if !metUnfinished || finding.isEmpty {
            flows[item] = most
        }
        metUnfinished = outerMet || (metUnfinished && !finding.isEmpty)
        return most
    }
}
