import DeslopModel

/// Turns a package's layout, its index and its syntax into the plain model.
/// Items come from the index's definitions, references from its other
/// non-implicit occurrences; the syntax says which properties are stored,
/// which declaration holds each reference, what the code does with a field
/// it names, and which functions are wrappers.
struct ModelBuilder {
    /// A file the index holds a record of, with its syntax.
    struct Source {
        let file: FileID
        let syntax: SourceSyntax
        let occurrences: [IndexOccurrence]
    }

    /// Where an item is defined: its file and the position of its name.
    private struct Site: Hashable {
        let file: FileID
        let position: SourcePosition
    }

    private var model: Model
    private let sources: [Source]
    private var itemOfUSR: [String: ItemID] = [:]
    /// Accessors (getters, setters, observers) by USR, to the USR of their property.
    private var propertyOfAccessor: [String: String] = [:]
    private var parentUSR: [ItemID: String] = [:]
    /// Extensions by USR, to the USR of the type each extends.
    private var extendedType: [String: String] = [:]
    /// The protocols the workspace and its imports declare.
    private var protocols: Protocols
    /// By the USR of a type or extension, the protocols it conforms to.
    private var conformances: [String: Set<String>] = [:]
    /// By the USR of a class, the classes it inherits from.
    private var superclasses: [String: Set<String>] = [:]
    private let syntaxOfFile: [FileID: SourceSyntax]
    private var itemAtSite: [Site: ItemID] = [:]
    private var siteOfItem: [ItemID: Site] = [:]
    /// By file and position, the items its references there name.
    private var namedAt: [Site: [ItemID]] = [:]
    /// Where the index names a type, of the workspace or not: what tells a
    /// call that constructs a value from any other call.
    private var typeSites: Set<Site> = []
    /// Where code calls a function, of the workspace or not, whose
    /// signature takes a writable key path, as its USR says.
    private var writableKeyPathCalls: Set<Site> = []
    /// By function, its USR, which says its signature.
    private var usrOfItem: [ItemID: String] = [:]
    /// By reference: where it is, and whether the index says it writes.
    private var referenceSites: [(site: Site, writes: Bool)] = []

    init(layout: Layout, sources: [Source], systemProtocols: Protocols = Protocols()) {
        protocols = systemProtocols
        model = Model(
            language: Language(name: "swift", pathSeparator: "."),
            tree: layout.tree,
            files: layout.entries.map(\.file)
        )
        self.sources = sources
        syntaxOfFile = Dictionary(uniqueKeysWithValues: sources.map { ($0.file, $0.syntax) })
    }

    /// The model, built.
    consuming func build() -> Model {
        for source in sources { addTypeSites(source) }
        for source in sources { addDefinitions(source) }
        markWitnesses()
        resolveInheritance()
        resolveParents()
        for source in sources { addReferences(source) }
        markCopies()
        let wrappers = findWrappers()
        model.wrappers = wrappers
        markLentReads()
        return model
    }

    // MARK: - Items

    private mutating func addTypeSites(_ source: Source) {
        for occurrence in source.occurrences
        where occurrence.roles.contains(.call) && occurrence.symbol.usr.contains("WritableKeyPath") {
            writableKeyPathCalls.insert(Site(file: source.file, position: SourcePosition(line: occurrence.line, column: occurrence.column)))
        }
        let types: Set<IndexSymbol.Kind> = [.struct, .class, .enum, .protocol, .union, .typeAlias]
        for occurrence in source.occurrences
        where occurrence.roles.contains(.reference) && types.contains(occurrence.symbol.kind)
            && occurrence.symbol.subkind != IndexSymbol.Subkind.swiftGenericTypeParameter {
            typeSites.insert(Site(file: source.file, position: SourcePosition(line: occurrence.line, column: occurrence.column)))
        }
    }

    /// The tokens of a field's type: as written, as its literal value says,
    /// or as the type its initial value constructs, where the index confirms
    /// the constructor is a type's name.
    private func fieldType(_ declaration: Declaration?, in file: FileID) -> [String]? {
        guard let declaration else { return nil }
        if let written = declaration.declaredType { return written }
        guard let constructed = declaration.constructed else { return nil }
        if let position = constructed.position, !typeSites.contains(Site(file: file, position: position)) {
            return nil
        }
        return constructed.tokens
    }

    private func fieldType(of item: ItemID) -> [String]? {
        guard let site = siteOfItem[item] else { return nil }
        return fieldType(declaration(of: item), in: site.file)
    }

    private mutating func addDefinitions(_ source: Source) {
        let module = model.file(source.file).module
        protocols.add(source.occurrences)
        for occurrence in source.occurrences {
            for relation in occurrence.relations {
                if relation.roles.contains(.extendedBy) {
                    extendedType[relation.symbol.usr] = occurrence.symbol.usr
                }
                guard relation.roles.contains(.baseOf) else { continue }
                switch occurrence.symbol.kind {
                case .protocol:
                    conformances[relation.symbol.usr, default: []].insert(occurrence.symbol.usr)
                case .class:
                    superclasses[relation.symbol.usr, default: []].insert(occurrence.symbol.usr)
                default:
                    break
                }
            }
        }
        for occurrence in source.occurrences
        where occurrence.roles.contains(.definition) && !occurrence.roles.contains(.implicit) {
            let symbol = occurrence.symbol
            if symbol.isLocal { continue }
            if symbol.isAccessor {
                if let property = occurrence.related(.accessorOf) {
                    propertyOfAccessor[symbol.usr] = property.usr
                }
                continue
            }
            let position = SourcePosition(line: occurrence.line, column: occurrence.column)
            let declaration = source.syntax.declaration(at: position)
            guard itemOfUSR[symbol.usr] == nil, let shape = ModelBuilder.shape(symbol, declaration) else { continue }
            // A witness of a conformance declared where the member is written
            // carries `overrideOf`; one declared elsewhere is told by
            // `markWitnesses`, once every conformance is known.
            let implementsInterface = symbol.kind == .destructor
                || occurrence.relations.contains { $0.roles.contains(.overrideOf) }
            let id = ItemID(model.items.count)
            model.items.append(Item(
                name: symbol.name,
                owner: module,
                file: source.file,
                kind: shape.kind,
                implementsInterface: implementsInterface,
                takesSelf: shape.takesSelf,
                holdsNothing: shape.kind == .field && fieldType(declaration, in: source.file).map(TypeFacts.holdsNothing) == true
            ))
            itemOfUSR[symbol.usr] = id
            usrOfItem[id] = symbol.usr
            if let parent = occurrence.related(.childOf) {
                parentUSR[id] = parent.usr
            }
            let site = Site(file: source.file, position: position)
            itemAtSite[site] = id
            siteOfItem[id] = site
        }
    }

    /// Marks as implementing an interface each function of a type that meets
    /// a requirement of a protocol the type conforms to, through any
    /// refinement: the index relates a witness to its requirement only when
    /// the conformance is declared where the witness is written, and a
    /// method written in a type's body may meet one declared in an empty
    /// extension. A function meets a requirement of its name whose signature,
    /// as their USRs write it, is its own; or, when the requirement's
    /// signature names `Self` or an associated type and so differs, when it
    /// is the only function of that name in its type.
    private mutating func markWitnesses() {
        var declaredBy: [String: Set<String>] = [:]
        for (conformer, declared) in conformances {
            declaredBy[extendedType[conformer] ?? conformer, default: []].formUnion(declared)
        }
        var sameName: [String: Int] = [:]
        for (item, usr) in parentUSR where model.item(item).kind == .function {
            sameName[(extendedType[usr] ?? usr) + " " + model.item(item).name, default: 0] += 1
        }
        for (item, usr) in parentUSR where model.item(item).kind == .function && !model.item(item).implementsInterface {
            let type = extendedType[usr] ?? usr
            let name = model.item(item).name
            let match = protocols.match(
                name,
                signature: usrOfItem[item].flatMap { Protocols.signature(usr: $0, name: name) },
                ofAny: declaredBy[type] ?? []
            )
            let only = sameName[type + " " + name] == 1
            if match == .signature || (match == .name && only) {
                model.items[item.index].implementsInterface = true
            }
        }
    }

    /// Sets the classes each class inherits from, as the index names them.
    private mutating func resolveInheritance() {
        for (subclass, bases) in superclasses {
            guard let type = itemOfUSR[extendedType[subclass] ?? subclass], model.item(type).kind == .type else { continue }
            let inherited = bases.compactMap { itemOfUSR[$0] }.filter { $0 != type && model.item($0).kind == .type }
            model.items[type.index].inherits = Array(Set(inherited)).sorted()
        }
    }

    /// What an index symbol is as an item, and whether it takes `self`;
    /// `nil` for what the model leaves out: extensions, parameters, generic
    /// parameters, modules, macros, and properties the source does not declare.
    private static func shape(_ symbol: IndexSymbol, _ declaration: Declaration?) -> (kind: ItemKind, takesSelf: Bool)? {
        let isSubscript = symbol.subkind == IndexSymbol.Subkind.swiftSubscript
        switch symbol.kind {
        case .struct, .class, .enum, .protocol, .union:
            return (.type, false)
        case .typeAlias:
            return symbol.subkind == IndexSymbol.Subkind.swiftGenericTypeParameter ? nil : (.type, false)
        case .function, .classMethod, .staticMethod, .constructor, .destructor:
            return (.function, false)
        case .instanceMethod:
            return (.function, true)
        case .enumConstant:
            return (.variant, false)
        case .variable:
            guard let declaration else { return nil }
            return declaration.kind == .storedProperty ? (.constant, false) : (.function, false)
        case .instanceProperty:
            if isSubscript { return (.function, true) }
            guard let declaration else { return nil }
            return declaration.kind == .storedProperty ? (.field, false) : (.function, true)
        case .classProperty, .staticProperty:
            if isSubscript { return (.function, false) }
            guard let declaration else { return nil }
            return declaration.kind == .storedProperty ? (.constant, false) : (.function, false)
        default:
            return nil
        }
    }

    /// Sets each member's parent, and names each item after what it is
    /// written in: `RunQueue.items`, `Outer.Inner.run()`. A member of an
    /// extension is the extended type's. A nested type is named after its
    /// outer type but is a thing of its own, as a type in a module is: it
    /// keeps its own fields and knows what it uses.
    private mutating func resolveParents() {
        var outer: [ItemID: ItemID] = [:]
        for (item, usr) in parentUSR {
            guard let parent = itemOfUSR[extendedType[usr] ?? usr], parent != item else { continue }
            outer[item] = parent
            if model.item(item).kind != .type {
                model.items[item.index].parent = parent
            }
        }
        let raw = model.items.map(\.name)
        for index in model.items.indices {
            var names = [raw[index]]
            var seen: Set<ItemID> = [ItemID(index)]
            var at = outer[ItemID(index)]
            while let parent = at, seen.insert(parent).inserted {
                names.insert(raw[parent.index], at: 0)
                at = outer[parent]
            }
            model.items[index].name = names.joined(separator: ".")
        }
    }

    // MARK: - References

    private mutating func addReferences(_ source: Source) {
        let module = model.file(source.file).module
        for occurrence in source.occurrences {
            let roles = occurrence.roles
            guard roles.contains(.reference), !roles.contains(.definition), !roles.contains(.implicit) else { continue }
            let usr = propertyOfAccessor[occurrence.symbol.usr] ?? occurrence.symbol.usr
            guard let item = itemOfUSR[usr] else { continue }
            let position = SourcePosition(line: occurrence.line, column: occurrence.column)
            var holder: ItemID?
            for name in source.syntax.holders(of: position) {
                if let found = itemAtSite[Site(file: source.file, position: name)] {
                    holder = found
                    break
                }
            }
            model.references.append(Reference(
                file: source.file,
                line: occurrence.line,
                from: module,
                holder: holder,
                item: item
            ))
            let site = Site(file: source.file, position: position)
            referenceSites.append((site, roles.contains(.write)))
            namedAt[site, default: []].append(item)
        }
    }

    private func syntax(of file: FileID) -> SourceSyntax? {
        syntaxOfFile[file]
    }

    /// What the index says of the names of `file` that its syntax cannot tell.
    private func facts(_ file: FileID) -> NameFacts {
        let namedAt = namedAt
        let items = model.items
        let writableKeyPathCalls = writableKeyPathCalls
        return NameFacts(
            isField: { position in
                (namedAt[Site(file: file, position: position)] ?? []).contains { items[$0.index].kind == .field }
            },
            takesWritableKeyPath: { position in
                writableKeyPathCalls.contains(Site(file: file, position: position))
            }
        )
    }

    private func declaration(of item: ItemID) -> Declaration? {
        guard let site = siteOfItem[item] else { return nil }
        return syntax(of: site.file)?.declaration(at: site.position)
    }

    /// Whether code that does `access` with `fields` only reads their values:
    /// uses a value, lends a view of plain data, or reaches a member of a scalar.
    private func onlyReads(_ access: Access, _ fields: [ItemID]) -> Bool {
        switch access {
        case .copy:
            return true
        case .borrow:
            return fields.allSatisfy { field in
                fieldType(of: field).map(TypeFacts.isData) ?? false
            }
        case .call:
            return fields.allSatisfy { field in
                fieldType(of: field).map(TypeFacts.isScalar) ?? false
            }
        case .reach:
            return false
        }
    }

    /// What the reference at `index` does with what it names.
    private func access(_ index: Int, propertyLike: Bool) -> Access {
        let (site, writes) = referenceSites[index]
        if writes { return .reach }
        guard let syntax = syntax(of: site.file) else { return .reach }
        let facts = facts(site.file)
        return propertyLike
            ? syntax.access(at: site.position, facts: facts)
            : syntax.callAccess(at: site.position, facts: facts)
    }

    /// Marks the references to fields that only read the field's value.
    private mutating func markCopies() {
        for index in model.references.indices {
            let field = model.references[index].item
            guard model.item(field).kind == .field else { continue }
            model.references[index].copies = onlyReads(access(index, propertyLike: true), [field])
        }
    }

    /// Marks the calls of accessors that lend to read, directly or through
    /// forwarders, that only read what they lend: `queue.head + 1` reads
    /// `_head` when `head` hands it out.
    private mutating func markLentReads() {
        for index in model.references.indices {
            let named = model.references[index].item
            var called = named
            var seen: Set<ItemID> = [called]
            while case .forwarder(let target, _) = model.wrappers[called], seen.insert(target).inserted {
                called = target
            }
            guard case .accessor(let lent, _, true) = model.wrappers[called], !lent.isEmpty else { continue }
            let kind = declaration(of: named)?.kind
            let propertyLike = kind == .computedProperty || kind == .subscript
            model.references[index].copies = onlyReads(access(index, propertyLike: propertyLike), lent)
        }
    }

    // MARK: - Wrappers

    private func findWrappers() -> [ItemID: Wrapper] {
        var wrappers: [ItemID: Wrapper] = [:]
        for forwarding in forwardings() where !reaches(wrappers, from: forwarding.target, to: forwarding.forwarder) {
            wrappers[forwarding.forwarder] = .forwarder(target: forwarding.target, fields: forwarding.fields)
        }
        var named: [ItemID: [ItemID]] = [:]
        for reference in model.references {
            if let holder = reference.holder, model.item(holder).kind == .function {
                named[holder, default: []].append(reference.item)
            }
        }
        for (function, names) in named.sorted(by: { $0.key < $1.key }) where wrappers[function] == nil {
            if let accessor = accessor(function, names: names) {
                wrappers[function] = accessor
            }
        }
        return wrappers
    }

    /// Each forwarder, in order, with the function it calls and the fields
    /// of `self` it calls it on. Its call passes as many operands as that
    /// function takes, its receiver counted.
    private func forwardings() -> [(forwarder: ItemID, target: ItemID, fields: [ItemID])] {
        var found: [(ItemID, ItemID, [ItemID])] = []
        for index in model.items.indices {
            let forwarder = ItemID(index)
            let item = model.item(forwarder)
            guard item.kind == .function, !item.implementsInterface,
                  let site = siteOfItem[forwarder],
                  let body = syntax(of: site.file)?.body(at: site.position),
                  let call = body.onlyCall else { continue }
            let at = { (position: SourcePosition) in self.namedAt[Site(file: site.file, position: position)] ?? [] }
            guard let target = at(call.callee).first(where: { model.item($0).kind == .function }), target != forwarder,
                  let targetDeclaration = declaration(of: target) else { continue }
            let propertyTarget = targetDeclaration.kind == .computedProperty
            guard call.isCall != propertyTarget else { continue }
            let passed = call.arguments.compactMap { $0 }
            guard passed.count == call.arguments.count, passed.allSatisfy(body.parameters.contains) else { continue }
            var fields: [ItemID] = []
            let receiver: Int
            switch call.base {
            case .unwritten:
                receiver = model.item(target).takesSelf ? 1 : 0
            case .parameter:
                guard call.path.isEmpty else { continue }
                receiver = 1
            case .selfValue, .implicitSelf:
                for position in call.path {
                    guard let field = at(position).first(where: { model.item($0).kind == .field }) else { break }
                    fields.append(field)
                }
                guard fields.count == call.path.count else { continue }
                receiver = 1
            }
            let takes = targetDeclaration.parameters.count + (model.item(target).takesSelf ? 1 : 0)
            if receiver + passed.count == takes {
                found.append((forwarder, target, fields))
            }
        }
        return found
    }

    /// Whether the chain of forwarders from `from` passes `to`.
    private func reaches(_ wrappers: [ItemID: Wrapper], from: ItemID, to: ItemID) -> Bool {
        var at = from
        var seen: Set<ItemID> = []
        while seen.insert(at).inserted {
            if at == to { return true }
            guard case .forwarder(let target, _) = wrappers[at] else { return false }
            at = target
        }
        return false
    }

    /// What `function` is as an accessor, if it is one: a method, computed
    /// property or subscript of a type, taking `self`, implementing no
    /// interface, whose body names only fields of its own type and types,
    /// computes nothing, and whose signature writes each field's type. What
    /// it hands out is lent: code that calls it does with the fields what it
    /// does with the call. It lends to read unless it is a method that writes.
    /// An initializer that only assigns its parameters to fields is one too:
    /// it adds nothing, as a Rust struct literal adds nothing, and code that
    /// calls it gives the fields their values whole.
    private func accessor(_ function: ItemID, names: [ItemID]) -> Wrapper? {
        let item = model.item(function)
        guard let own = item.parent, !item.implementsInterface,
              let site = siteOfItem[function],
              let declaration = syntax(of: site.file)?.declaration(at: site.position),
              let body = syntax(of: site.file)?.body(at: site.position),
              !body.computes else { return nil }
        let initializer = declaration.kind == .initializer
        guard item.takesSelf || initializer else { return nil }
        var fields: Set<ItemID> = []
        for name in names {
            let named = model.item(name)
            switch named.kind {
            case .field where named.parent == own:
                fields.insert(name)
            case .type, .module, .impl:
                continue
            default:
                return nil
            }
        }
        let typed = fields.allSatisfy { field in
            guard let written = self.fieldType(of: field), !written.isEmpty else { return false }
            return body.signature.count >= written.count
                && (0...(body.signature.count - written.count)).contains { Array(body.signature[$0..<$0 + written.count]) == written }
        }
        guard !fields.isEmpty, typed else { return nil }
        if initializer {
            return .accessor(lent: [], copied: fields.sorted(), toRead: true)
        }
        let propertyLike = declaration.kind == .computedProperty || declaration.kind == .subscript
        return .accessor(lent: fields.sorted(), copied: [], toRead: propertyLike || !body.writes)
    }
}
