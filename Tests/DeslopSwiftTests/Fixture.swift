import Foundation

/// A copy of one of `Fixtures/`'s packages, with one of its variants' files
/// over it, to build and lint apart from every other test. A variant holds
/// only the files it changes, and lists in `REMOVED` those it deletes.
struct Fixture {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    let directory: URL

    init(_ family: String, variant: String? = nil) throws {
        let manager = FileManager.default
        directory = manager.temporaryDirectory
            .appendingPathComponent("deslop-tests-\(UUID().uuidString)")
            .appendingPathComponent(family)
        try manager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: Fixture.root.appendingPathComponent(family), to: directory)
        if let variant {
            try Fixture.overlay(Fixture.root.appendingPathComponent("variants/\(family)/\(variant)"), onto: directory)
        }
    }

    private static func overlay(_ source: URL, onto target: URL) throws {
        let manager = FileManager.default
        for entry in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
            let destination = target.appendingPathComponent(entry.lastPathComponent)
            if entry.lastPathComponent == "REMOVED" {
                let removed = try String(contentsOf: entry, encoding: .utf8).split(separator: "\n")
                for path in removed {
                    try manager.removeItem(at: target.appendingPathComponent(String(path)))
                }
            } else if try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true)
                try overlay(entry, onto: destination)
            } else {
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }
                try manager.copyItem(at: entry, to: destination)
            }
        }
    }

    /// Removes the copy.
    func remove() throws {
        try FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }
}
