/// Compiler-style colors: bold red errors, bold blue gutter, bold green
/// success. Without color, text is left as it is.
public struct Paint: Sendable {
    public let colored: Bool

    public init(colored: Bool) {
        self.colored = colored
    }

    func error(_ text: String) -> String { sgr("1;31", text) }
    func gutter(_ text: String) -> String { sgr("1;34", text) }
    func ok(_ text: String) -> String { sgr("1;32", text) }
    func bold(_ text: String) -> String { sgr("1", text) }

    private func sgr(_ code: String, _ text: String) -> String {
        colored ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}
