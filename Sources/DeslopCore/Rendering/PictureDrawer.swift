/// The picture under each report, in box-drawing characters. What the
/// report is about is drawn heavy, and in red when there is color, so it
/// reads the same without.
public struct PictureDrawer: Sendable {
    /// The longest bar, in cells: with a list's name and length, a line fits
    /// in 80 columns. A longer list's bar ends in `⋯`. The line at the most is
    /// no further than halfway along it.
    static let bar = 40

    let paint: Paint

    public init(paint: Paint) {
        self.paint = paint
    }

    /// The lines of `picture`, indented to sit under a report's notes.
    public func draw(_ picture: Picture) -> [String] {
        let lines: [String]
        switch picture {
        case .circle(let steps, let rest):
            lines = circle(steps, rest: rest)
        case .spread(let owner, let field, let modules, let others):
            lines = spread(owner: owner, field: field, modules: modules, others: others)
        case .lists(let shown, let hidden, let lists):
            let rows = [("shows", shown, true), ("hides", hidden, false)] + lists.map { ($0.name, $0.length, true) }
            lines = bars(rows, most: Text.heldInMind)
        case .bar(let label, let length, let most):
            lines = bars([(label, length, true)], most: most)
        }
        return lines.map { "    " + $0 }
    }

    /// Each member under the last, the tie to the next between them, and the
    /// last tie back up to the first. The first tie, the cheapest, is heavy.
    private func circle(_ steps: [Step], rest: String?) -> [String] {
        let sites = shortSites(steps)
        let width = sites.map(\.count).max() ?? 0
        var lines: [String] = []
        for (index, (step, site)) in zip(steps, sites).enumerated() {
            let cheapest = index == 0
            func heavy(_ light: String, _ heavy: String) -> String {
                cheapest ? paint.error(heavy) : light
            }
            let into = cheapest ? "┌─▶ " : "│   "
            lines.append(into + paint.bold(step.member))
            lines.append("│     \(heavy("│", "┃")) \(padded(site, width))  \(step.uses)")
            if index + 1 < steps.count {
                lines.append("│     \(heavy("▼", "▼"))")
            }
        }
        lines.append("└─────┘")
        if let rest { lines.append(rest) }
        return lines
    }

    /// `kinds.rs:10` for `src/kinds.rs:10`: each step's site, from the
    /// directory all of them are in.
    private func shortSites(_ steps: [Step]) -> [String] {
        func directory(_ step: Step) -> [Substring] {
            Array(step.site.file.split(separator: "/", omittingEmptySubsequences: false).dropLast())
        }
        var common = steps.first.map(directory) ?? []
        for step in steps {
            let parts = directory(step)
            let same = zip(common, parts).prefix { $0 == $1 }.count
            common = Array(common.prefix(same))
        }
        let skip = common.reduce(0) { $0 + $1.utf8.count + 1 }
        return steps.map { step in
            let file = String(decoding: step.site.file.utf8.dropFirst(skip), as: UTF8.self)
            return "\(file):\(step.site.line)"
        }
    }

    /// The type, then the field with an arm from each module that works on
    /// it, then its other fields.
    private func spread(owner: String, field: String, modules: [Picture.Spread], others: [String]) -> [String] {
        var lines = [owner]
        let digits = modules.map { String($0.places).count }.max() ?? 0
        let under = String(repeating: " ", count: field.count + 3)
        for (index, module) in modules.enumerated() {
            let lead: String
            let arm: String
            if index == 0 {
                lead = "  \(paint.bold(field)) "
                arm = modules.count == 1 ? "◀━━━" : "◀━┳━"
            } else if index + 1 == modules.count {
                lead = under
                arm = "  ┗━"
            } else {
                lead = under
                arm = "  ┣━"
            }
            lines.append("\(lead)\(paint.error(arm)) \(rightAligned(String(module.places), digits))  \(module.module)")
        }
        lines.append(contentsOf: others.map { "  " + $0 })
        return lines
    }

    /// A bar for each of `rows`, by its name and length, with a line at
    /// `most`; past it, a judged row's bar is heavy. A cell is one, or as many
    /// as put the line halfway along the longest bar, and part of one fills one.
    private func bars(_ rows: [(String, Int, Bool)], most: Int) -> [String] {
        let unit = max(ceilingDivision(most, Self.bar / 2), 1)
        let line = ceilingDivision(most, unit)
        let width = rows.map(\.0.count).max() ?? 0
        var lines = ["\(padded("", width))  \(rightAligned(String(most), line + 1))"]
        for (name, length, judged) in rows {
            let cells = ceilingDivision(length, unit)
            let inside = min(cells, line)
            let past = cells - inside
            var beyond = String(repeating: "█", count: min(past, Self.bar - line))
            if past > Self.bar - line { beyond += "⋯" }
            if judged && past > 0 { beyond = paint.error(beyond) }
            let full = String(repeating: "█", count: inside)
            let empty = String(repeating: " ", count: line - inside)
            lines.append("\(padded(name, width))  \(full)\(empty)│\(beyond) \(length)")
        }
        return lines
    }

    private func ceilingDivision(_ value: Int, _ divisor: Int) -> Int {
        (value + divisor - 1) / divisor
    }

    private func padded(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(width - text.count, 0))
    }

    private func rightAligned(_ text: String, _ width: Int) -> String {
        String(repeating: " ", count: max(width - text.count, 0)) + text
    }
}
