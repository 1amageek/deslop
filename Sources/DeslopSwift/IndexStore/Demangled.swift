import CSwiftRuntime
import Foundation

/// The text of Swift manglings, as the Swift runtime demangles them. A
/// mangling's own text cannot be searched for a name: it writes a word it
/// has written before as a back reference, so in `Machine`, `scaleMachine`
/// is written `05scaleB0`.
enum Demangled {
    /// The demangled text of the Swift declaration `usr` names:
    /// `Lib.Box.subscript(path: Swift.WritableKeyPath<Lib.Q, Swift.Int>) -> Swift.Int`.
    /// `nil` for a USR that is not a Swift declaration's, or that the
    /// runtime does not demangle.
    static func text(ofUSR usr: String) -> String? {
        guard isSwiftDeclaration(usr) else { return nil }
        return demangle("$s" + usr.dropFirst(2))
    }

    /// Whether `usr` names a Swift declaration, whose USR is its mangling.
    /// An extension's (`s:e:`) names the extended type instead.
    static func isSwiftDeclaration(_ usr: String) -> Bool {
        usr.hasPrefix("s:") && !usr.hasPrefix("s:e:")
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
}
