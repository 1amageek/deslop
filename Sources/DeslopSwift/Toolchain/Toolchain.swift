import Foundation

/// The `swift` on the path: what builds the package, writes its index, and
/// ships the libIndexStore that reads that index.
struct Toolchain: Sendable {
    let runner: CommandRunner

    /// libIndexStore of the toolchain whose compiler writes the index: next to
    /// its runtime resources, `<toolchain>/usr/lib`. `DESLOP_LIBINDEXSTORE`
    /// names another.
    /// `swift`, as `prefix` runs it: `["swift"]` from the path, `["xcrun", "swift"]` as Xcode's.
    func indexStoreLibrary(swift prefix: [String] = ["swift"], environment: [String: String]? = nil) throws(FrontendError) -> URL {
        if let override = ProcessInfo.processInfo.environment["DESLOP_LIBINDEXSTORE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        struct TargetInfo: Decodable {
            struct Paths: Decodable { let runtimeResourcePath: String }
            let paths: Paths
        }
        let data = try runner.run(prefix + ["-print-target-info"], environment: environment)
        let info: TargetInfo
        do {
            info = try JSONDecoder().decode(TargetInfo.self, from: data)
        } catch {
            throw .indexStoreLibraryUnavailable("`swift -print-target-info` is unreadable: \(error)")
        }
        #if os(macOS)
        let name = "libIndexStore.dylib"
        #else
        let name = "libIndexStore.so"
        #endif
        return URL(fileURLWithPath: info.paths.runtimeResourcePath)
            .deletingLastPathComponent()
            .appendingPathComponent(name)
    }

    /// Builds the package at `root` in `scratch`, writing its index.
    func buildIndex(root: URL, scratch: URL) throws(FrontendError) {
        let arguments = [
            "swift", "build",
            "--package-path", root.path,
            "--scratch-path", scratch.path,
            "--enable-index-store",
        ]
        let output = try runner.runAllowingFailure(arguments)
        guard output.status == 0 else {
            let printed = String(decoding: output.standardOutput, as: UTF8.self) + output.standardError
            throw .commandFailed(command: arguments.joined(separator: " "), status: output.status, output: printed)
        }
    }

    /// The index store a build in `scratch` wrote: the directory holding its
    /// `v5` units. The `swiftbuild` build system writes it to `out/`, the
    /// `native` one to `<triple>/debug/index/store/` (linked from
    /// `debug/index/store/`); of those that exist, the most recently written
    /// is the build's.
    func indexStore(in scratch: URL) throws(FrontendError) -> URL {
        let manager = FileManager.default
        let triples: [URL]
        do {
            triples = try manager.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)
        } catch {
            throw .indexStoreMissing(scratchPath: scratch.path)
        }
        let candidates = [scratch.appendingPathComponent("out"), scratch.appendingPathComponent("debug/index/store")]
            + triples.map { $0.appendingPathComponent("debug/index/store") }
        var found: [(store: URL, modified: Date)] = []
        for store in candidates {
            let units = store.appendingPathComponent("v5/units")
            guard manager.fileExists(atPath: units.path) else { continue }
            do {
                let modified = try units.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                found.append((store, modified ?? .distantPast))
            } catch {
                throw .indexStoreUnreadable("\(units.path): \(error)")
            }
        }
        guard let newest = found.max(by: { $0.modified < $1.modified }) else {
            throw .indexStoreMissing(scratchPath: scratch.path)
        }
        return newest.store
    }
}
