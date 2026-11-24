import DeslopModel
import Foundation

/// The hierarchy and files of a SwiftPM package: each Swift target is a
/// package node, each directory below a target's root a module node, and
/// each source file of a target a file of the module its directory is.
struct PackageLayout {
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
        /// Whether the build compiles it into a module the lints read: a
        /// source of a non-test, non-plugin target.
        let indexed: Bool
    }

    private(set) var tree = Tree()
    private(set) var entries: [Entry] = []

    init(package: PackageDescription) throws(FrontendError) {
        let root = URL(fileURLWithPath: package.path)
        let targets = package.targets.filter(\.isSwift).sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        for target in targets {
            let node = tree.child(of: Tree.root, kind: .package, name: target.name)
            tree.setTest(node, target.isTest)
            let sources = (target.sources ?? []).filter { $0.hasSuffix(".swift") }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for source in sources {
                let path = PackageLayout.joined(target.path, source)
                let directories = source.split(separator: "/").dropLast().map(String.init)
                var module = node
                for directory in directories {
                    module = tree.child(of: module, kind: .module, name: directory)
                }
                let url = root.appendingPathComponent(path)
                let text: String
                let modified: Date
                let byteOrderMark: Int
                do {
                    let data = try Data(contentsOf: url)
                    byteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
                    guard let decoded = String(validating: data.dropFirst(byteOrderMark), as: UTF8.self) else {
                        throw FrontendError.sourceUnreadable(path: path, reason: "not UTF-8 text")
                    }
                    text = decoded
                    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                    guard let date = values.contentModificationDate else {
                        throw FrontendError.sourceUnreadable(path: path, reason: "no modification date")
                    }
                    modified = date
                } catch let error as FrontendError {
                    throw error
                } catch {
                    throw .sourceUnreadable(path: path, reason: String(describing: error))
                }
                let (rank, declares) = PackageLayout.rank(source: source, target: target)
                let file = SourceFile(
                    path: path,
                    module: module,
                    test: target.isTest,
                    lines: PackageLayout.lineCount(text),
                    rank: rank,
                    declares: declares
                )
                entries.append(Entry(
                    file: file,
                    absolutePath: IndexStoreReader.canonical(url.path),
                    text: text,
                    byteOrderMark: byteOrderMark,
                    modified: modified,
                    indexed: !target.isTest && target.type != "plugin"
                ))
            }
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
    private static func rank(source: String, target: PackageDescription.Target) -> (Int, String?) {
        let parts = source.split(separator: "/").map(String.init)
        guard let name = parts.last else { return (2, nil) }
        let lowered = name.lowercased()
        if parts.count == 1, lowered == "main.swift" || lowered == "\(target.name).swift".lowercased() {
            return (0, target.path)
        }
        if parts.count >= 2, lowered == "\(parts[parts.count - 2]).swift".lowercased() {
            return (1, joined(target.path, parts.dropLast().joined(separator: "/")))
        }
        return (2, nil)
    }

    private static func joined(_ directory: String, _ path: String) -> String {
        directory.isEmpty || directory == "." ? path : directory + "/" + path
    }
}
