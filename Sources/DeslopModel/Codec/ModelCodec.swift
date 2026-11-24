import Foundation

/// Reads and writes the JSON form of a model, and checks that what it reads
/// holds the model's invariants.
public enum ModelCodec {
    public static func encode(_ model: Model) throws(ModelError) -> Data {
        let wrappers = model.wrappers.sorted { $0.key < $1.key }.map { function, wrapper in
            entry(function: function, wrapper: wrapper)
        }
        let document = ModelDocument(
            format: ModelDocument.format,
            version: ModelDocument.version,
            language: model.language,
            nodes: model.tree.nodes,
            files: model.files,
            items: model.items,
            references: model.references,
            wrappers: wrappers
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        do {
            return try encoder.encode(document)
        } catch {
            throw .malformed(String(describing: error))
        }
    }

    public static func decode(_ data: Data) throws(ModelError) -> Model {
        let document: ModelDocument
        do {
            document = try JSONDecoder().decode(ModelDocument.self, from: data)
        } catch {
            throw .malformed(String(describing: error))
        }
        guard document.format == ModelDocument.format, document.version == ModelDocument.version else {
            throw .unsupportedFormat(format: document.format, version: document.version)
        }
        try validateNodes(document.nodes)
        var wrappers: [ItemID: Wrapper] = [:]
        for (index, entry) in document.wrappers.enumerated() {
            guard wrappers[entry.function] == nil else { throw .duplicateWrapper(function: entry.function.index) }
            wrappers[entry.function] = try wrapper(entry, index: index)
        }
        let model = Model(
            language: document.language,
            tree: Tree(validatedNodes: document.nodes),
            files: document.files,
            items: document.items,
            references: document.references,
            wrappers: wrappers
        )
        try validate(model)
        return model
    }

    /// Checks every invariant the lints rely on, for a model built in memory.
    public static func validate(_ model: Model) throws(ModelError) {
        try validateNodes(model.tree.nodes)
        guard !model.language.pathSeparator.isEmpty else { throw .emptyPathSeparator }
        let nodes = model.tree.count
        let files = model.files.count
        let items = model.items.count
        func check(_ value: Int, below count: Int, _ part: String, _ index: Int, _ field: String) throws(ModelError) {
            guard value >= 0, value < count else {
                throw .dangling(part: part, index: index, field: field, value: value)
            }
        }
        for (index, file) in model.files.enumerated() {
            try check(file.module.index, below: nodes, "file", index, "module")
            guard !file.path.isEmpty, !file.path.hasPrefix("/"), file.lines >= 0, (0...3).contains(file.rank) else {
                throw .invalidFile(file: index)
            }
        }
        for (index, item) in model.items.enumerated() {
            try check(item.owner.index, below: nodes, "item", index, "owner")
            if let module = item.module { try check(module.index, below: nodes, "item", index, "module") }
            if let file = item.file { try check(file.index, below: files, "item", index, "file") }
            if let parent = item.parent { try check(parent.index, below: items, "item", index, "parent") }
            for inherited in item.inherits { try check(inherited.index, below: items, "item", index, "inherits") }
        }
        for (index, item) in model.items.enumerated() where !item.inherits.isEmpty {
            guard item.kind == .type, item.inherits.allSatisfy({ model.items[$0.index].kind == .type }) else {
                throw .invalidInheritance(item: index)
            }
        }
        try validateInheritance(model.items)
        for index in model.items.indices {
            var seen: Set<Int> = [index]
            var at = model.items[index].parent
            while let parent = at {
                guard seen.insert(parent.index).inserted else { throw .parentCycle(item: index) }
                at = model.items[parent.index].parent
            }
        }
        for (index, reference) in model.references.enumerated() {
            try check(reference.file.index, below: files, "reference", index, "file")
            try check(reference.from.index, below: nodes, "reference", index, "from")
            try check(reference.item.index, below: items, "reference", index, "item")
            if let holder = reference.holder { try check(holder.index, below: items, "reference", index, "holder") }
            guard reference.line >= 1 else { throw .invalidLine(reference: index, line: reference.line) }
        }
        let sortedWrappers = model.wrappers.sorted { $0.key < $1.key }
        for (function, wrapper) in sortedWrappers {
            try check(function.index, below: items, "wrapper", function.index, "function")
            switch wrapper {
            case .forwarder(let target, let fields):
                try check(target.index, below: items, "wrapper", function.index, "target")
                for field in fields { try check(field.index, below: items, "wrapper", function.index, "fields") }
            case .accessor(let lent, let copied, _):
                for field in lent + copied { try check(field.index, below: items, "wrapper", function.index, "fields") }
            }
        }
        for (function, _) in sortedWrappers {
            var seen: Set<ItemID> = [function]
            var at = function
            while case .forwarder(let target, _) = model.wrappers[at] {
                guard seen.insert(target).inserted else { throw .forwarderCycle(function: function.index) }
                at = target
            }
        }
    }

    /// The tree's invariants: the first node is the workspace and the only
    /// one; each other node's parent precedes it; a package is inside the
    /// workspace or a package, a module inside a package or a module; and no
    /// two children of one node share a kind and a name.
    private static func validateNodes(_ nodes: [Node]) throws(ModelError) {
        guard let first = nodes.first, first.parent == nil, first.kind == .workspace else {
            throw .misplacedRoot(node: 0)
        }
        struct Sibling: Hashable {
            let parent: Int
            let kind: NodeKind
            let name: String
        }
        var siblings: Set<Sibling> = []
        for (index, node) in nodes.enumerated().dropFirst() {
            guard let parent = node.parent, node.kind != .workspace else { throw .misplacedRoot(node: index) }
            guard parent.index >= 0, parent.index < index else {
                throw .parentAfterChild(node: index, parent: parent.index)
            }
            if node.kind == .module, nodes[parent.index].kind == .workspace {
                throw .moduleOutsidePackage(node: index)
            }
            guard siblings.insert(Sibling(parent: parent.index, kind: node.kind, name: node.name)).inserted else {
                throw .duplicateNode(node: index)
            }
        }
    }

    /// No chain of inheritance comes back to where it started.
    private static func validateInheritance(_ items: [Item]) throws(ModelError) {
        // 0: not seen, 1: on the current chain, 2: done.
        var state = [UInt8](repeating: 0, count: items.count)
        for start in items.indices where state[start] == 0 && !items[start].inherits.isEmpty {
            var stack: [(item: Int, next: Int)] = [(start, 0)]
            state[start] = 1
            while let (item, next) = stack.last {
                let inherited = items[item].inherits
                guard next < inherited.count else {
                    state[item] = 2
                    stack.removeLast()
                    continue
                }
                stack[stack.count - 1].next += 1
                let to = inherited[next].index
                if state[to] == 1 { throw .inheritanceCycle(item: start) }
                if state[to] == 0 {
                    state[to] = 1
                    stack.append((to, 0))
                }
            }
        }
    }

    private static func entry(function: ItemID, wrapper: Wrapper) -> ModelDocument.WrapperEntry {
        switch wrapper {
        case .forwarder(let target, let fields):
            ModelDocument.WrapperEntry(
                function: function,
                forwarder: .init(target: target, fields: fields),
                accessor: nil
            )
        case .accessor(let lent, let copied, let toRead):
            ModelDocument.WrapperEntry(
                function: function,
                forwarder: nil,
                accessor: .init(lent: lent, copied: copied, toRead: toRead)
            )
        }
    }

    private static func wrapper(_ entry: ModelDocument.WrapperEntry, index: Int) throws(ModelError) -> Wrapper {
        switch (entry.forwarder, entry.accessor) {
        case (let forwarder?, nil):
            return .forwarder(target: forwarder.target, fields: forwarder.fields)
        case (nil, let accessor?):
            return .accessor(lent: accessor.lent, copied: accessor.copied, toRead: accessor.toRead)
        default:
            throw .malformed("wrapper \(index): exactly one of `forwarder` and `accessor` is required")
        }
    }
}
