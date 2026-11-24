/// What a symbol's signature declares of key paths, as its USR, demangled,
/// says: in its type, its parameters or its result.
enum KeyPathSignature: Int, Sendable, Comparable {
    /// Declares no writable key path: one it takes or hands out only reads.
    case readOnly
    /// A Swift USR the runtime does not demangle: it may declare one.
    case unknown
    /// Declares a `WritableKeyPath` or a `ReferenceWritableKeyPath`.
    case writable

    /// The signature `usr` writes. Only a Swift declaration can declare a
    /// Swift key path.
    init(usr: String) {
        guard Demangled.isSwiftDeclaration(usr) else {
            self = .readOnly
            return
        }
        guard let text = Demangled.text(ofUSR: usr) else {
            self = .unknown
            return
        }
        self.init(text: text)
    }

    /// What the demangled signature `text` declares.
    init(text: String) {
        self = text.contains("Swift.WritableKeyPath<") || text.contains("Swift.ReferenceWritableKeyPath<")
            ? .writable
            : .readOnly
    }

    static func < (lhs: KeyPathSignature, rhs: KeyPathSignature) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
