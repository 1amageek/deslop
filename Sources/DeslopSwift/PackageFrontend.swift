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
        let layout = try Layout(root: URL(fileURLWithPath: package.path), targets: package.layoutTargets)
        guard layout.entries.contains(where: \.indexed) else {
            return try ModelAssembly.model(layout, reader: nil)
        }
        if buildsIndex {
            try toolchain.buildIndex(root: packageRoot, scratch: scratchPath)
        }
        let store = try toolchain.indexStore(in: scratchPath)
        let library = try IndexStoreLibrary(at: try toolchain.indexStoreLibrary())
        return try ModelAssembly.model(layout, reader: IndexStoreReader(library: library, store: store))
    }
}
