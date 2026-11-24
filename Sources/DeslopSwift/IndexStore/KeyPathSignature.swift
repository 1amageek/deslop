import CSwiftRuntime
import Foundation

/// What a symbol's signature declares of key paths, as its USR, demangled,
/// says: in its type, its parameters or its result.
enum KeyPathSignature: Int, Sendable, Comparable {
    /// Declares no writable key path: one it takes or hands out only reads.
    case readOnly
    /// A Swift USR the runtime does not demangle: it may declare one.
    case unknown
    /// Declares a `WritableKeyPath` or a `ReferenceWritableKeyPath`.
    case writable

    /// The signature `usr` writes. The text of a mangled name cannot be
    /// searched for a type's name, since a mangling writes a word it has
    /// written before as a back reference: `write(keyPath:)` writes its
    /// parameter's type as `s011WritableKeyD0C`. So the USR is demangled.
    init(usr: String) {
        // Only a Swift declaration can declare a Swift key path; an
        // extension's USR (`s:e:`) names the extended type, not a signature.
        guard usr.hasPrefix("s:"), !usr.hasPrefix("s:e:") else {
            self = .readOnly
            return
        }
        guard let text = KeyPathSignature.demangle("$s" + usr.dropFirst(2)) else {
            self = .unknown
            return
        }
        self = text.contains("Swift.WritableKeyPath<") || text.contains("Swift.ReferenceWritableKeyPath<")
            ? .writable
            : .readOnly
    }

    /// The text the Swift runtime demangles `mangled` to; `nil` when it is
    /// not a Swift mangling.
    static func demangle(_ mangled: String) -> String? {
        var mangled = mangled
        return mangled.withUTF8 { bytes -> String? in
            guard let base = bytes.baseAddress else { return nil }
            let name = base.withMemoryRebound(to: CChar.self, capacity: bytes.count) { $0 }
            // The runtime allocates the result with `malloc`; it is copied
            // into a `String` here and freed exactly once.
            guard let demangled = swift_demangle(name, bytes.count, nil, nil, 0) else { return nil }
            defer { free(demangled) }
            return String(cString: demangled)
        }
    }

    static func < (lhs: KeyPathSignature, rhs: KeyPathSignature) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
