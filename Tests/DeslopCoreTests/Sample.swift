import DeslopCore
import DeslopModel

/// Small Rust-flavored models for the graph's and the lints' tests, as
/// deslop-please's own tests build them: one crate, `p`, with one file for
/// each module. That the lints report the same of them as deslop-please
/// does shows they hold no knowledge of the language.
struct Sample {
    var model = Model(language: Language(name: "rust", pathSeparator: "::"))

    init() {
        _ = model.tree.child(of: Tree.root, kind: .package, name: "p")
    }

    var crate: NodeID {
        mutating get { model.tree.child(of: Tree.root, kind: .package, name: "p") }
    }

    /// The module at `path` below the crate, `""` for the crate itself.
    mutating func module(_ path: String) -> NodeID {
        var node = crate
        for name in path.split(separator: "::") {
            node = model.tree.child(of: node, kind: .module, name: String(name))
        }
        if !model.files.contains(where: { $0.module == node }) {
            let file = "src/" + path.split(separator: "::", omittingEmptySubsequences: false).joined(separator: "/") + ".rs"
            model.files.append(Sample.rustFile(file, module: node, lines: 1))
        }
        return node
    }

    /// A file of `module`'s at `path`, of `lines` lines.
    mutating func file(_ module: NodeID, _ path: String, lines: Int) {
        model.files.append(Sample.rustFile(path, module: module, lines: lines))
    }

    mutating func item(_ owner: NodeID, _ name: String, _ kind: ItemKind) -> ItemID {
        let file = model.files.firstIndex { $0.module == owner }.map(FileID.init)
        model.items.append(Item(name: name, owner: owner, file: file, kind: kind))
        return ItemID(model.items.count - 1)
    }

    /// An item of `parent`'s, written in `owner`.
    mutating func member(_ parent: ItemID, _ owner: NodeID, _ name: String, _ kind: ItemKind) -> ItemID {
        let id = item(owner, name, kind)
        model.items[id.index].parent = parent
        return id
    }

    /// A reference to `item` in `holder`'s code, on a line of its own.
    mutating func refer(_ holder: ItemID, _ item: ItemID) {
        let from = model.item(holder).owner
        let file = model.files.firstIndex { $0.module == from }!
        model.references.append(Reference(
            file: FileID(file),
            line: model.references.count + 1,
            from: from,
            holder: holder,
            item: item
        ))
    }

    /// The same, where the code only takes a copy of `item`'s value.
    mutating func read(_ holder: ItemID, _ item: ItemID) {
        refer(holder, item)
        model.references[model.references.count - 1].copies = true
    }

    mutating func setTakesSelf(_ item: ItemID, _ value: Bool = true) {
        model.items[item.index].takesSelf = value
    }

    func named(_ name: String) -> ItemID {
        ItemID(model.items.firstIndex { $0.name == name }!)
    }

    var graph: Graph { Graph(model: model) }

    func context(scope: NodeID? = nil) -> LintContext {
        LintContext(model: model, scope: scope)
    }

    /// Rust's conventions for where a reader starts a module: `lib.rs` first,
    /// then `mod.rs` and `main.rs`, then any file, then examples; and the
    /// directory a file declares: its own for `lib.rs`, `mod.rs` and
    /// `main.rs`, the one beside it for any other.
    static func rustFile(_ path: String, module: NodeID, lines: Int) -> SourceFile {
        let rank: Int
        if path.hasSuffix("/src/lib.rs") || path == "src/lib.rs" {
            rank = 0
        } else if path.hasSuffix("/mod.rs") || path.hasSuffix("src/main.rs") {
            rank = 1
        } else if path.contains("/examples/") {
            rank = 3
        } else {
            rank = 2
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let name = parts.last.map(String.init) ?? path
        let declares: String
        if ["mod.rs", "lib.rs", "main.rs"].contains(name) {
            declares = parts.dropLast().joined(separator: "/")
        } else {
            declares = String(path.dropLast(3))
        }
        return SourceFile(path: path, module: module, test: false, lines: lines, rank: rank, declares: declares)
    }
}
