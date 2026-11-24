import Foundation

/// A SwiftPM package written to a temporary directory from its sources:
/// one library target, `Lib`, holding `sources` at their paths.
struct TemporaryPackage {
    let directory: URL

    init(target: String = "Lib", sources: [String: String]) throws {
        let manager = FileManager.default
        directory = manager.temporaryDirectory.appendingPathComponent("deslop-package-\(UUID().uuidString)")
        let manifest = """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(name: "\(target)", platforms: [.macOS(.v15)], targets: [.target(name: "\(target)")])

            """
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("Package.swift"))
        for (path, text) in sources {
            let file = directory.appendingPathComponent("Sources/\(target)/\(path)")
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
    }

    func url(_ path: String) -> URL {
        directory.appendingPathComponent(path)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directory)
    }
}
