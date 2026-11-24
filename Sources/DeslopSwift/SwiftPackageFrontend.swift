import DeslopModel
import Foundation

/// The model of a SwiftPM package: its description says its targets and
/// files, a build writes its index, and the source text says the rest.
public struct SwiftPackageFrontend: ModelSource {
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
        packageRoot.appendingPathComponent(".build/swift-deslop", isDirectory: true)
    }

    public func model() throws(SwiftFrontendError) -> Model {
        let runner = CommandRunner()
        let toolchain = SwiftToolchain(runner: runner)
        let package = try SwiftPackage.describe(packageRoot, runner: runner)
        let layout = try PackageLayout(package: package)
        let indexed = layout.entries.enumerated().filter { $0.element.indexed }
        var occurrences: [String: [IndexOccurrence]] = [:]
        if !indexed.isEmpty {
            if buildsIndex {
                try toolchain.buildIndex(root: packageRoot, scratch: scratchPath)
            }
            let store = try toolchain.indexStore(in: scratchPath)
            let library = try IndexStoreLibrary(at: try toolchain.indexStoreLibrary())
            let reader = IndexStoreReader(library: library, store: store)
            occurrences = try reader.occurrences(of: Set(indexed.map(\.element.absolutePath)))
        }
        var sources: [SwiftModelBuilder.Source] = []
        for (index, entry) in indexed {
            guard let found = occurrences[entry.absolutePath] else {
                throw .sourceNotIndexed(path: entry.file.path)
            }
            sources.append(SwiftModelBuilder.Source(
                file: FileID(index),
                syntax: SourceSyntax(text: entry.text, fileName: entry.file.path),
                occurrences: found.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
            ))
        }
        let model = SwiftModelBuilder(layout: layout, sources: sources).build()
        do {
            try ModelCodec.validate(model)
        } catch {
            throw .invalidModel(error)
        }
        return model
    }
}
