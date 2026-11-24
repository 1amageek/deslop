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

    /// What the index holds of one file: when it was compiled, and its occurrences.
    struct Indexed {
        let compiled: IndexUnit.Time
        let occurrences: [IndexOccurrence]
    }

    /// What the index holds of a package's files, and of the protocols of
    /// the modules those files import.
    struct Read {
        /// By file (absolute, symlinks resolved).
        let files: [String: Indexed]
        /// From the records of system modules: their protocols' requirements
        /// and refinements.
        let systemProtocols: Protocols
    }

    /// By each of `files` (absolute, symlinks resolved), what the index holds
    /// of it, occurrences in the order the index keeps them; and the protocols
    /// of the system modules the index records. Of the units that compiled a
    /// file, the latest is read; a file no unit compiled is missing from the
    /// result.
    func read(_ files: Set<String>) throws(FrontendError) -> Read {
        let handle = try library.openStore(at: store.path)
        defer { library.close(handle) }
        var latest: [String: (record: String, modified: IndexUnit.Time)] = [:]
        var systemRecords: Set<String> = []
        for name in library.unitNames(in: handle) {
            let unit = try library.unit(name, in: handle)
            systemRecords.formUnion(unit.records.filter(\.isSystem).map(\.name))
            guard !unit.isSystem, let mainFile = unit.mainFile else { continue }
            let main = IndexStoreReader.canonical(mainFile)
            guard files.contains(main) else { continue }
            if let known = latest[main], known.modified >= unit.modified { continue }
            if let record = unit.records.first(where: { !$0.isSystem && IndexStoreReader.canonical($0.path) == main }) {
                latest[main] = (record.name, unit.modified)
            }
        }
        var result: [String: Indexed] = [:]
        for (file, chosen) in latest {
            let occurrences = try library.occurrences(ofRecord: chosen.record, in: handle)
            result[file] = Indexed(compiled: chosen.modified, occurrences: occurrences)
        }
        var protocols = Protocols()
        for record in systemRecords.sorted() {
            protocols.add(try library.occurrences(ofRecord: record, in: handle))
        }
        return Read(files: result, systemProtocols: protocols)
    }

    /// `path`, absolute, with symbolic links resolved: how files are compared.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
