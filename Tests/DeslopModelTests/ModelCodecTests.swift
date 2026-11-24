import Foundation
import Testing
@testable import DeslopModel

@Suite("Model JSON contract")
struct ModelCodecTests {
    /// A model with one of each part: a package `p` with module `m`, a type
    /// with a field, a getter that is an accessor, and a reference.
    private func sample() -> Model {
        var tree = Tree()
        let package = tree.child(of: Tree.root, kind: .package, name: "p")
        let module = tree.child(of: package, kind: .module, name: "m")
        let file = SourceFile(path: "Sources/p/m/T.swift", module: module, test: false, lines: 3, rank: 1, declares: "Sources/p/m")
        let type = Item(name: "T", owner: module, file: FileID(0), kind: .type)
        let field = Item(name: "T.x", owner: module, file: FileID(0), kind: .field, parent: ItemID(0))
        let getter = Item(name: "T.value", owner: module, file: FileID(0), kind: .function, parent: ItemID(0), takesSelf: true)
        let reference = Reference(file: FileID(0), line: 2, from: module, holder: ItemID(2), item: ItemID(1), copies: true)
        return Model(
            language: Language(name: "swift", pathSeparator: "."),
            tree: tree,
            files: [file],
            items: [type, field, getter],
            references: [reference],
            wrappers: [ItemID(2): .accessor(lent: [ItemID(1)], copied: [], toRead: true)]
        )
    }

    private func json(_ model: Model) throws -> [String: Any] {
        let data = try ModelCodec.encode(model)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws(ModelError) -> Model {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw .malformed("test fixture: \(error)")
        }
        return try ModelCodec.decode(data)
    }

    @Test("a model round-trips through its JSON form")
    func roundTrip() throws {
        let model = sample()
        let decoded = try ModelCodec.decode(try ModelCodec.encode(model))
        #expect(decoded.language == model.language)
        #expect(decoded.tree.nodes == model.tree.nodes)
        #expect(decoded.files == model.files)
        #expect(decoded.items == model.items)
        #expect(decoded.references == model.references)
        #expect(decoded.wrappers == model.wrappers)
        #expect(decoded.tree.node(NodeID(2)).name == "m")
    }

    @Test("the JSON form names its format and version")
    func header() throws {
        let object = try json(sample())
        #expect(object["format"] as? String == "deslop-model")
        #expect(object["version"] as? Int == 1)
    }

    @Test("another format or version is rejected")
    func unsupportedFormat() throws {
        var object = try json(sample())
        object["version"] = 2
        #expect(throws: ModelError.unsupportedFormat(format: "deslop-model", version: 2)) {
            try decode(object)
        }
    }

    @Test("an index that names nothing is rejected with where it is")
    func dangling() throws {
        var object = try json(sample())
        var references = try #require(object["references"] as? [[String: Any]])
        references[0]["item"] = 9
        object["references"] = references
        #expect(throws: ModelError.dangling(part: "reference", index: 0, field: "item", value: 9)) {
            try decode(object)
        }
    }

    @Test("a node whose parent comes after it is rejected")
    func parentAfterChild() throws {
        var object = try json(sample())
        var nodes = try #require(object["nodes"] as? [[String: Any]])
        nodes[1]["parent"] = 2
        object["nodes"] = nodes
        #expect(throws: ModelError.parentAfterChild(node: 1, parent: 2)) {
            try decode(object)
        }
    }

    @Test("a loop of item parents is rejected")
    func parentCycle() throws {
        var object = try json(sample())
        var items = try #require(object["items"] as? [[String: Any]])
        items[0]["parent"] = 1
        object["items"] = items
        #expect(throws: ModelError.parentCycle(item: 0)) {
            try decode(object)
        }
    }

    @Test("a loop of forwarders is rejected")
    func forwarderCycle() throws {
        var model = sample()
        model.wrappers = [
            ItemID(1): .forwarder(target: ItemID(2), fields: []),
            ItemID(2): .forwarder(target: ItemID(1), fields: []),
        ]
        #expect(throws: ModelError.forwarderCycle(function: 1)) {
            try ModelCodec.validate(model)
        }
    }

    @Test("a wrapper that is both or neither kind is malformed")
    func ambiguousWrapper() throws {
        var object = try json(sample())
        object["wrappers"] = [["function": 2]]
        #expect(throws: ModelError.self) {
            try decode(object)
        }
    }

    @Test("text that is not a model is malformed")
    func notJSON() {
        #expect(throws: ModelError.self) {
            try ModelCodec.decode(Data("not json".utf8))
        }
    }
}

@Suite("Model contract invariants")
struct ModelInvariantTests {
    /// One package `P` with one module `m`, a file, and two functions.
    private func base() -> Model {
        var tree = Tree()
        let package = tree.child(of: Tree.root, kind: .package, name: "P")
        let module = tree.child(of: package, kind: .module, name: "m")
        return Model(
            language: Language(name: "swift", pathSeparator: "."),
            tree: tree,
            files: [SourceFile(path: "Sources/P/m/A.swift", module: module, test: false, lines: 1, rank: 2)],
            items: [
                Item(name: "f()", owner: module, file: FileID(0), kind: .function),
                Item(name: "g()", owner: module, file: FileID(0), kind: .function),
            ]
        )
    }

    /// The JSON form of `base()`, edited by `edit`, decoded.
    private func decodeEdited(_ edit: (inout [String: Any]) -> Void) throws -> Model {
        let data = try ModelCodec.encode(base())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&object)
        return try ModelCodec.decode(try JSONSerialization.data(withJSONObject: object))
    }

    private func editNode(_ index: Int, _ key: String, _ value: Any) -> (inout [String: Any]) -> Void {
        { object in
            var nodes = object["nodes"] as? [[String: Any]] ?? []
            nodes[index][key] = value
            object["nodes"] = nodes
        }
    }

    @Test("the root is the workspace, and no other node is one")
    func nodeKinds() {
        #expect(throws: ModelError.misplacedRoot(node: 0)) { try decodeEdited(editNode(0, "kind", "package")) }
        #expect(throws: ModelError.misplacedRoot(node: 2)) { try decodeEdited(editNode(2, "kind", "workspace")) }
    }

    @Test("a module is inside a package")
    func moduleInsidePackage() {
        #expect(throws: ModelError.moduleOutsidePackage(node: 1)) { try decodeEdited(editNode(1, "kind", "module")) }
    }

    @Test("two children of one node do not share a kind and a name")
    func uniqueSiblings() {
        #expect(throws: ModelError.duplicateNode(node: 3)) {
            try decodeEdited { object in
                var nodes = object["nodes"] as? [[String: Any]] ?? []
                nodes.append(["name": "m", "kind": "module", "parent": 1, "test": false])
                object["nodes"] = nodes
            }
        }
    }

    @Test("the path separator is not empty")
    func emptySeparator() {
        var model = base()
        model.language.pathSeparator = ""
        #expect(throws: ModelError.emptyPathSeparator) { try ModelCodec.validate(model) }
    }

    @Test("a file has a non-empty relative path, zero or more lines, and a rank of 0 to 3")
    func fileValues() {
        let changes: [(inout SourceFile) -> Void] = [
            { $0.lines = -1 },
            { $0.rank = 9 },
            { $0.path = "/abs/A.swift" },
            { $0.path = "" },
        ]
        for change in changes {
            var model = base()
            change(&model.files[0])
            #expect(throws: ModelError.invalidFile(file: 0)) { try ModelCodec.validate(model) }
        }
    }

    @Test("a function has at most one wrapper entry")
    func duplicateWrapper() {
        #expect(throws: ModelError.duplicateWrapper(function: 0)) {
            try decodeEdited { object in
                object["wrappers"] = [
                    ["function": 0, "forwarder": ["target": 1, "fields": [Int]()]],
                    ["function": 0, "accessor": ["lent": [Int](), "copied": [Int](), "toRead": true]],
                ]
            }
        }
    }

    @Test("a type inherits only types, and no chain of inheritance loops")
    func inheritance() {
        var function = base()
        function.items[0].inherits = [ItemID(1)]
        #expect(throws: ModelError.invalidInheritance(item: 0)) { try ModelCodec.validate(function) }

        var looping = base()
        looping.items[0].kind = .type
        looping.items[1].kind = .type
        looping.items[0].inherits = [ItemID(1)]
        looping.items[1].inherits = [ItemID(0)]
        #expect(throws: ModelError.inheritanceCycle(item: 0)) { try ModelCodec.validate(looping) }

        var dangling = base()
        dangling.items[0].kind = .type
        dangling.items[0].inherits = [ItemID(7)]
        #expect(throws: ModelError.dangling(part: "item", index: 0, field: "inherits", value: 7)) {
            try ModelCodec.validate(dangling)
        }
    }
}
