import DeslopModel

/// Builds the model of a layout from the index a build wrote: reads the
/// occurrences of each indexed file, checks that the index describes the
/// text as it is, and validates what the builder makes.
enum ModelAssembly {
    /// The model of `layout`; `reader` reads the index, and is `nil` only
    /// when the layout has no indexed file.
    static func model(_ layout: Layout, reader: IndexStoreReader?) throws(FrontendError) -> Model {
        let entries = layout.entries.enumerated().filter { $0.element.indexed }
        var indexed: [String: IndexStoreReader.Indexed] = [:]
        var systemProtocols = Protocols()
        if !entries.isEmpty {
            guard let reader else {
                preconditionFailure("a layout with indexed files is assembled with a reader of their index")
            }
            let read = try reader.read(Set(entries.map(\.element.absolutePath)))
            indexed = read.files
            systemProtocols = read.systemProtocols
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
        let model = ModelBuilder(layout: layout, sources: sources, systemProtocols: systemProtocols).build()
        do {
            try ModelCodec.validate(model)
        } catch {
            throw .invalidModel(error)
        }
        return model
    }
}
