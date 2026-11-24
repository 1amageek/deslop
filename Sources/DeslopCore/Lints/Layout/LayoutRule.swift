import DeslopModel

/// `wide-directory` and `long-file`: how the code is laid out in files. A
/// reader takes in a directory by listing it and finds their way in a file
/// by scrolling through it, so each has a most it holds. A directory's
/// members are its source files and its directories that hold source files;
/// a file's lines are all of them, blank and comment lines too; test code
/// counts like any other. A directory concerns a package or module when one
/// of its files is below it.
public struct LayoutRule: LintRule {
    /// The most files and directories one directory holds. Past fifteen
    /// names, a listing is searched rather than read, and its files want
    /// directories of their own, by what they are about.
    static let mostMembers = 15

    /// The most lines one file has. Past 2,000, a file holds parts that want
    /// files of their own.
    static let mostLines = 2_000

    public init() {}

    public func check(_ context: LintContext) -> [Diagnostic] {
        let model = context.model
        var diagnostics = model.files
            .filter { $0.lines > Self.mostLines && context.hierarchy.isWithin($0.module, context.scope) }
            .map(longFile)
        // By directory, its members, and whether a file below it is in scope.
        var directories: [String: (members: Set<String>, below: Bool)] = [:]
        for file in model.files {
            for (directory, member) in Self.holders(file.path) {
                var entry = directories[directory] ?? ([], false)
                entry.members.insert(member)
                entry.below = entry.below || context.hierarchy.isWithin(file.module, context.scope)
                directories[directory] = entry
            }
        }
        let wide = directories
            .filter { $0.value.below && $0.value.members.count > Self.mostMembers }
            .sorted { Text.precedes($0.key, $1.key) }
            .map { wideDirectory(model, directory: $0.key, members: $0.value.members) }
        diagnostics.append(contentsOf: wide)
        return diagnostics
    }

    /// Each directory that holds `path`, outermost first, `""` for the root,
    /// with the member it holds `path` by: `src/lint/cycles.rs` is in the
    /// root by `src/`, in `src` by `lint/`, and in `src/lint` by `cycles.rs`.
    static func holders(_ path: String) -> [(directory: String, member: String)] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var held: [(String, String)] = []
        var directory: [String] = []
        for (index, part) in parts.enumerated() {
            let last = index == parts.count - 1
            held.append((directory.joined(separator: "/"), last ? part : part + "/"))
            directory.append(part)
        }
        return held
    }

    private func longFile(_ file: SourceFile) -> Diagnostic {
        Diagnostic(
            lint: .longFile,
            key: file.path,
            message: "`\(file.path)` is long: it has \(file.lines) lines, more than \(Self.mostLines)",
            location: Location(file: file.path, line: 1),
            notes: [],
            picture: .bar(label: "lines", length: file.lines, most: Self.mostLines)
        )
    }

    /// The report of `directory`, which holds `members`.
    private func wideDirectory(_ model: Model, directory: String, members: Set<String>) -> Diagnostic {
        let shown = directory.isEmpty ? "./" : directory + "/"
        let sortedMembers = Text.sorted(Array(members))
        let directories = sortedMembers.filter { $0.hasSuffix("/") }
        let files = sortedMembers.filter { !$0.hasSuffix("/") }
        let notes = [(files, "file", "files"), (directories, "directory", "directories")]
            .filter { !$0.0.isEmpty }
            .map { names, one, many in "\(names.count) \(names.count == 1 ? one : many): \(Text.listed(names))" }
        // The file that declares its members: in it, or beside it.
        let declaring = model.files
            .filter { $0.declares == directory }
            .min { a, b in a.rank != b.rank ? a.rank < b.rank : Text.precedes(a.path, b.path) }
        return Diagnostic(
            lint: .wideDirectory,
            key: shown,
            message: "`\(shown)` is wide: it holds \(members.count) files and directories, more than \(Self.mostMembers)",
            location: declaring.map { Location(file: $0.path, line: 1) },
            notes: notes,
            picture: .bar(label: "holds", length: members.count, most: Self.mostMembers)
        )
    }
}
