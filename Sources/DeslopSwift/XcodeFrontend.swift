import DeslopModel
import Foundation

/// The model of an Xcode project or workspace: its projects say its targets
/// and where their files are, a build of its schemes writes the index, the
/// index says which files each target compiled, and the source text says
/// the rest.
public struct XcodeFrontend: ModelSource {
    public let root: URL
    public let project: String?
    public let workspace: String?
    /// The schemes to build; every scheme the container defines when empty.
    public let schemes: [String]
    /// Where to build; chosen per scheme when `nil`.
    public let destination: String?
    /// The toolchain `xcodebuild` builds with; Xcode's when `nil`.
    public let toolchain: String?
    /// Whether to build before reading the index. Without, the index of the
    /// last build is read.
    public let buildsIndex: Bool

    public init(
        root: URL,
        project: String? = nil,
        workspace: String? = nil,
        schemes: [String] = [],
        destination: String? = nil,
        toolchain: String? = nil,
        buildsIndex: Bool = true
    ) {
        self.root = root
        self.project = project
        self.workspace = workspace
        self.schemes = schemes
        self.destination = destination
        self.toolchain = toolchain
        self.buildsIndex = buildsIndex
    }

    /// Where the frontend builds, apart from the project's own builds.
    public var derivedData: URL {
        root.appendingPathComponent(".build/deslop/xcode", isDirectory: true)
    }

    public func model() throws(FrontendError) -> Model {
        let runner = CommandRunner()
        let container = try XcodeContainer.locate(root: root, project: project, workspace: workspace)
        var targets: [XcodeProjectFile.Target] = []
        for project in container.projects {
            targets += try XcodeProjectFile.read(project, root: root, runner: runner).targets
        }
        let build = XcodeBuild(runner: runner, container: container, toolchain: toolchain)
        if buildsIndex {
            let defined = try build.schemes(
                targets: Set(targets.map(\.name)),
                testTargets: Set(targets.filter(\.isTest).map(\.name))
            )
            for scheme in schemes where !defined.contains(scheme) {
                throw .schemeNotFound(scheme: scheme, available: defined)
            }
            for scheme in schemes.isEmpty ? defined : schemes {
                let destination: String
                if let chosen = self.destination {
                    destination = chosen
                } else {
                    destination = try build.destination(of: scheme)
                }
                try build.build(scheme: scheme, destination: destination, derivedData: derivedData)
            }
        }
        let store = derivedData.appendingPathComponent("Index.noindex/DataStore")
        guard FileManager.default.fileExists(atPath: store.appendingPathComponent("v5/units").path) else {
            throw .indexStoreMissing(scratchPath: derivedData.path)
        }
        let library = try IndexStoreLibrary(at: try Toolchain(runner: runner).indexStoreLibrary(
            swift: ["xcrun", "swift"], environment: build.environment
        ))
        let reader = IndexStoreReader(library: library, store: store)
        let compiled = try reader.compiledFiles()
        let layout = try Layout(root: root, targets: try XcodeFrontend.layoutTargets(
            targets, compiled: compiled, root: root, derivedData: derivedData, schemesNamed: !schemes.isEmpty
        ))
        return try ModelAssembly.model(layout, reader: reader)
    }

    /// The targets of the layout: each project target, with the files the
    /// index says it compiled, or, for a test target, those the project
    /// lists for it; and each module of a local package below the root.
    /// `schemesNamed`: only some schemes were built, so a target none of
    /// them compiled is left unchecked rather than an error.
    static func layoutTargets(
        _ targets: [XcodeProjectFile.Target],
        compiled: [(module: String, file: String)],
        root: URL,
        derivedData: URL,
        schemesNamed: Bool
    ) throws(FrontendError) -> [LayoutTarget] {
        let rootPath = IndexStoreReader.canonical(root.path)
        let derivedPath = IndexStoreReader.canonical(derivedData.path)
        var byModule: [String: [String]] = [:]
        for (module, file) in compiled where file.hasPrefix(rootPath + "/") && !file.hasPrefix(derivedPath + "/") {
            byModule[module, default: []].append(String(file.dropFirst(rootPath.count + 1)))
        }
        var layout: [LayoutTarget] = []
        var claimed: Set<String> = []
        for target in targets {
            let module = [target.name, XcodeFrontend.moduleName(target.name)].first { byModule[$0] != nil }
            if let module, let files = byModule[module], !target.isTest {
                claimed.insert(module)
                layout.append(LayoutTarget(
                    name: target.name,
                    isTest: false,
                    root: target.synchronizedFolders.first ?? XcodeFrontend.commonDirectory(files),
                    sources: files,
                    indexed: true
                ))
            } else if target.isTest {
                layout.append(LayoutTarget(
                    name: target.name,
                    isTest: true,
                    root: target.synchronizedFolders.first ?? XcodeFrontend.commonDirectory(target.listedSources),
                    sources: target.listedSources,
                    indexed: false
                ))
            } else if !target.listedSources.isEmpty {
                // Checking some schemes leaves the rest out on purpose; checking
                // all and missing a target would report it clean unseen.
                guard schemesNamed else { throw .targetNotBuilt(target: target.name) }
                layout.append(LayoutTarget(
                    name: target.name,
                    isTest: false,
                    root: target.synchronizedFolders.first ?? XcodeFrontend.commonDirectory(target.listedSources),
                    sources: target.listedSources,
                    indexed: false
                ))
            }
        }
        for (module, files) in byModule where !claimed.contains(module) {
            layout.append(LayoutTarget(
                name: module,
                isTest: false,
                root: XcodeFrontend.commonDirectory(files),
                sources: files,
                indexed: true
            ))
        }
        return layout
    }

    /// The module name Xcode gives a target by default: its name, with each
    /// character that cannot be in an identifier made `_`.
    static func moduleName(_ target: String) -> String {
        var name = String(target.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        if name.first?.isNumber == true { name = "_" + name }
        return name
    }

    /// The directory all of `files` are in, `""` for the root.
    static func commonDirectory(_ files: [String]) -> String {
        let directories = files.map { $0.split(separator: "/").dropLast().map(String.init) }
        guard var common = directories.first else { return "" }
        for parts in directories.dropFirst() {
            common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
        }
        return common.joined(separator: "/")
    }
}
