import DeslopModel
import Foundation

/// The model of a SwiftPM package: its description says its targets and
/// files, a build writes its index, and the source text says the rest.
public struct PackageFrontend: ModelSource {
    public let packageRoot: URL
    /// Whether to build the package, writing its index, before reading it.
    /// Without, the index of the last build is read.
    public let buildsIndex: Bool

    public init(packageRoot: URL, buildsIndex: Bool = true) {
        self.packageRoot = packageRoot
        self.buildsIndex = buildsIndex
    }

    /// Where the frontend builds, apart from the package's own builds.
    public var scratchPath: URL {
        packageRoot.appendingPathComponent(".build/deslop", isDirectory: true)
    }

    public func model() throws(FrontendError) -> Model {
        let runner = CommandRunner()
        let toolchain = Toolchain(runner: runner)
        let package = try PackageDescription.describe(packageRoot, runner: runner)
        let layout = try PackageLayout(package: package)
        let entries = layout.entries.enumerated().filter { $0.element.indexed }
        var indexed: [String: IndexStoreReader.Indexed] = [:]
        if !entries.isEmpty {
            if buildsIndex {
                try toolchain.buildIndex(root: packageRoot, scratch: scratchPath)
            }
            let store = try toolchain.indexStore(in: scratchPath)
            let library = try IndexStoreLibrary(at: try toolchain.indexStoreLibrary())
            let reader = IndexStoreReader(library: library, store: store)
            indexed = try reader.occurrences(of: Set(entries.map(\.element.absolutePath)))
        }
        var sources: [ModelBuilder.Source] = []
        for (index, entry) in entries {
            guard let found = indexed[entry.absolutePath] else {
                throw .sourceNotIndexed(path: entry.file.path)
            }
            // The index's positions are those of the text it compiled; text
            // changed since would put its names at other places.
            guard !found.compiled.precedes(entry.modified) else {
                throw .indexStale(path: entry.file.path)
            }
            sources.append(ModelBuilder.Source(
                file: FileID(index),
                syntax: SourceSyntax(text: entry.text, fileName: entry.file.path, byteOrderMark: entry.byteOrderMark),
                occurrences: found.occurrences.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
            ))
        }
        let model = ModelBuilder(layout: layout, sources: sources).build()
        do {
            try ModelCodec.validate(model)
        } catch {
            throw .invalidModel(error)
        }
        return model
    }
}
