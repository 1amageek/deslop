import DeslopModel
import Foundation

/// The hierarchy and files of what is built: each target is a package
/// node, each directory below a target's root a module node, and each
/// source file of a target a file of the module its directory is. A file
/// outside its target's root is the target's own.
struct Layout {
    /// A source file, and what the frontend needs of it beyond the model.
    struct Entry {
        let file: SourceFile
        /// Absolute, symlinks resolved: how the index names it.
        let absolutePath: String
        let text: String
        /// UTF-8 bytes of a byte order mark the file starts with, which
        /// reading it as text drops and the index's columns count.
        let byteOrderMark: Int
        /// When the file was last written.
        let modified: Date
        /// Whether the build compiles it into a module the lints read.
        let indexed: Bool
    }

    private(set) var tree = Tree()
    private(set) var entries: [Entry] = []

    /// The layout of `targets`, whose paths are relative to `root`. Targets
    /// come in name order; a file two targets list is the first's.
    init(root: URL, targets: [LayoutTarget]) throws(FrontendError) {
        var seen: Set<String> = []
        for target in targets.sorted(by: { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }) {
            let node = tree.child(of: Tree.root, kind: .package, name: target.name)
            tree.setTest(node, target.isTest)
            for path in target.sources.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                guard seen.insert(path).inserted else { continue }
                let inside = Layout.relative(path, to: target.root)
                var module = node
                for directory in (inside?.split(separator: "/").dropLast() ?? []) {
                    module = tree.child(of: module, kind: .module, name: String(directory))
                }
                let url = root.appendingPathComponent(path)
                let (text, byteOrderMark, modified) = try Layout.read(url, path: path)
                let (rank, declares) = inside.map { Layout.rank(source: $0, target: target) } ?? (2, nil)
                let file = SourceFile(
                    path: path,
                    module: module,
                    test: target.isTest,
                    lines: Layout.lineCount(text),
                    rank: rank,
                    declares: declares
                )
                entries.append(Entry(
                    file: file,
                    absolutePath: IndexStoreReader.canonical(url.path),
                    text: text,
                    byteOrderMark: byteOrderMark,
                    modified: modified,
                    indexed: target.indexed
                ))
            }
        }
    }

    /// `path` relative to `directory`, when it is inside it.
    private static func relative(_ path: String, to directory: String) -> String? {
        if directory.isEmpty || directory == "." { return path }
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    /// A file's text, without a byte order mark it starts with, the mark's
    /// length, and when the file was last written.
    private static func read(_ url: URL, path: String) throws(FrontendError) -> (String, Int, Date) {
        do {
            let data = try Data(contentsOf: url)
            let byteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            guard let text = String(validating: data.dropFirst(byteOrderMark), as: UTF8.self) else {
                throw FrontendError.sourceUnreadable(path: path, reason: "not UTF-8 text")
            }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values.contentModificationDate else {
                throw FrontendError.sourceUnreadable(path: path, reason: "no modification date")
            }
            return (text, byteOrderMark, modified)
        } catch let error as FrontendError {
            throw error
        } catch {
            throw .sourceUnreadable(path: path, reason: String(describing: error))
        }
    }

    /// Every line of `text`, blank and comment lines too; a last line with no
    /// line break counts, an empty one after the last break does not.
    static func lineCount(_ text: String) -> Int {
        var count = 0
        var pending = false
        for byte in text.utf8 {
            if byte == UInt8(ascii: "\n") {
                count += 1
                pending = false
            } else {
                pending = true
            }
        }
        return count + (pending ? 1 : 0)
    }

    /// Where a reader starts: `main.swift` or `<Target>.swift` at a target's
    /// root is the target's root file; `<Dir>.swift` in `<Dir>/` declares
    /// its directory. Names compare in any case: target `tool` has `Tool.swift`.
    private static func rank(source: String, target: LayoutTarget) -> (Int, String?) {
        let parts = source.split(separator: "/").map(String.init)
        guard let name = parts.last else { return (2, nil) }
        let lowered = name.lowercased()
        if parts.count == 1, lowered == "main.swift" || lowered == "\(target.name).swift".lowercased() {
            return (0, target.root)
        }
        if parts.count >= 2, lowered == "\(parts[parts.count - 2]).swift".lowercased() {
            return (1, joined(target.root, parts.dropLast().joined(separator: "/")))
        }
        return (2, nil)
    }

    private static func joined(_ directory: String, _ path: String) -> String {
        directory.isEmpty || directory == "." ? path : directory + "/" + path
    }
}
