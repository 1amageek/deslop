/// Compiler-style report formatting, with a picture under each report.
public struct Renderer: Sendable {
    /// The command whose output this is: the last line names it.
    let tool: String
    let paint: Paint

    public init(tool: String, colored: Bool) {
        self.tool = tool
        self.paint = Paint(colored: colored)
    }

    /// The report of `diagnostics`; `fixedAllowed` allowed entries of the
    /// allowlist at `allowPath` are no longer reported.
    public func render(_ diagnostics: [Diagnostic], fixedAllowed: Int = 0, allowPath: String? = nil) -> String {
        let drawer = PictureDrawer(paint: paint)
        var out = ""
        for diagnostic in diagnostics {
            out += paint.error("error[\(diagnostic.lint.name)]") + paint.bold(": \(diagnostic.message)") + "\n"
            if let location = diagnostic.location {
                out += "  \(paint.gutter("-->")) \(location.file):\(location.line):1\n"
            }
            for note in diagnostic.notes {
                out += "  \(paint.gutter("=")) \(paint.bold("note:")) \(note)\n"
            }
            for line in drawer.draw(diagnostic.picture) {
                out += line + "\n"
            }
            out += "\n"
        }
        if fixedAllowed > 0, let path = allowPath {
            let noun = fixedAllowed == 1 ? "entry" : "entries"
            out += "\(paint.bold("note:")) \(fixedAllowed) allowed \(noun) in \(path) are now fixed "
                + "(run `\(tool) --update-allow \(path)` to tighten it)\n"
        }
        if diagnostics.isEmpty {
            out += "\(tool): \(paint.ok("ok"))\n"
        } else {
            let noun = diagnostics.count == 1 ? "error" : "errors"
            out += "\(tool): \(paint.error("\(diagnostics.count) \(noun)")), well done!\n"
        }
        return out
    }
}
