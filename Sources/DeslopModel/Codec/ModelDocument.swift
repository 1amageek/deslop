/// The JSON form of a model, as frontends write it and `ModelCodec` reads it.
struct ModelDocument: Codable {
    struct WrapperEntry: Codable {
        struct Forwarder: Codable {
            var target: ItemID
            var fields: [ItemID]
        }

        struct Accessor: Codable {
            var lent: [ItemID]
            var copied: [ItemID]
            var toRead: Bool
        }

        var function: ItemID
        var forwarder: Forwarder?
        var accessor: Accessor?
    }

    static let format = "deslop-model"
    static let version = 1

    var format: String
    var version: Int
    var language: Language
    var nodes: [Node]
    var files: [SourceFile]
    var items: [Item]
    var references: [Reference]
    var wrappers: [WrapperEntry]
}
