import CIndexStore
import Foundation

/// Reads the occurrences an index store holds for a set of source files.
struct IndexStoreReader {
    private let library: IndexStoreLibrary
    private let store: URL

    init(library: IndexStoreLibrary, store: URL) {
        self.library = library
        self.store = store
    }

    /// By each of `files` (absolute, symlinks resolved), its occurrences in
    /// the order the index keeps them. Of the units that compiled a file,
    /// the latest is read; a file no unit compiled is missing from the result.
    func occurrences(of files: Set<String>) throws(SwiftFrontendError) -> [String: [IndexOccurrence]] {
        let handle = try library.openStore(at: store.path)
        defer { library.close(handle) }
        var latest: [String: (record: String, modified: IndexUnit.Time)] = [:]
        for name in library.unitNames(in: handle) {
            let unit = try library.unit(name, in: handle)
            guard !unit.isSystem, let mainFile = unit.mainFile else { continue }
            let main = IndexStoreReader.canonical(mainFile)
            guard files.contains(main) else { continue }
            if let known = latest[main], known.modified >= unit.modified { continue }
            if let record = unit.records.first(where: { IndexStoreReader.canonical($0.path) == main }) {
                latest[main] = (record.name, unit.modified)
            }
        }
        var result: [String: [IndexOccurrence]] = [:]
        for (file, chosen) in latest {
            result[file] = try library.occurrences(ofRecord: chosen.record, in: handle)
        }
        return result
    }

    /// `path`, absolute, with symbolic links resolved: how files are compared.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
