import DeslopModel
import Testing
@testable import DeslopCore

@Suite("wide-directory and long-file")
struct LayoutTests {
    private func letters(_ count: Int) -> [String] {
        "abcdefghijklmnopqrstuvwxyz".prefix(count).map(String.init)
    }

    /// A sample whose crate, `p`, has its root at `src/lib.rs`, and the crate's node.
    private func crateP() -> (Sample, NodeID) {
        var sample = Sample()
        let p = sample.crate
        sample.file(p, "src/lib.rs", lines: 1)
        return (sample, p)
    }

    private func keys(_ sample: Sample, scope: NodeID? = nil) -> [String] {
        LayoutRule().check(sample.context(scope: scope)).map { "\($0.lint.name) \($0.key)" }
    }

    @Test("a directory of more than fifteen files and directories is wide")
    func wideDirectory() {
        var (sample, _) = crateP()
        for name in letters(14) { _ = sample.module(name) }
        #expect(keys(sample).isEmpty)
        _ = sample.module("o::p")
        let diagnostics = LayoutRule().check(sample.context())
        #expect(diagnostics.count == 1)
        let wide = diagnostics[0]
        #expect(wide.key == "src/")
        #expect(wide.message == "`src/` is wide: it holds 16 files and directories, more than 15")
        #expect(wide.location == Location(file: "src/lib.rs", line: 1))
        #expect(wide.notes == ["15 files: a.rs, b.rs, c.rs, d.rs, e.rs, f.rs, g.rs, +8 more", "1 directory: o/"])
        #expect(wide.picture == .bar(label: "holds", length: 16, most: 15))
    }

    @Test("a wide directory is found where its modules are declared")
    func wideDirectoryLocation() {
        var (sample, _) = crateP()
        let store = sample.module("store")
        for name in letters(16) {
            sample.file(store, "src/store/\(name).rs", lines: 1)
            sample.file(store, "tests/\(name).rs", lines: 1)
        }
        func location(_ key: String) -> Location?? {
            LayoutRule().check(sample.context()).first { $0.key == key }.map(\.location)
        }
        #expect(location("src/store/") == .some(Location(file: "src/store.rs", line: 1)))
        #expect(location("tests/") == .some(nil))
        sample.file(store, "src/store/mod.rs", lines: 1)
        #expect(location("src/store/") == .some(Location(file: "src/store/mod.rs", line: 1)))
    }

    @Test("a file of more than 2000 lines is long")
    func longFile() {
        var (sample, p) = crateP()
        sample.file(p, "src/table.rs", lines: 2_000)
        #expect(keys(sample).isEmpty)
        sample.model.files[sample.model.files.count - 1].lines = 2_001
        let diagnostics = LayoutRule().check(sample.context())
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].key == "src/table.rs")
        #expect(diagnostics[0].message == "`src/table.rs` is long: it has 2001 lines, more than 2000")
    }

    @Test("a wide directory concerns what is below it, and a long file its module")
    func scope() {
        var (sample, p) = crateP()
        let modules = letters(15).map { sample.module($0) }
        sample.model.files[1].lines = 2_001
        let q = sample.model.tree.child(of: Tree.root, kind: .package, name: "q")
        sample.file(q, "q/src/lib.rs", lines: 1)
        let both = ["long-file src/a.rs", "wide-directory src/"]
        #expect(keys(sample) == both)
        #expect(keys(sample, scope: p) == both)
        #expect(keys(sample, scope: modules[0]) == both)
        #expect(keys(sample, scope: modules[1]) == ["wide-directory src/"])
        #expect(keys(sample, scope: q).isEmpty)
    }

    @Test("a path is held by each directory above it")
    func holders() {
        let held = LayoutRule.holders("src/lint/cycles.rs").map { [$0.directory, $0.member] }
        #expect(held == [["", "src/"], ["src", "lint/"], ["src/lint", "cycles.rs"]])
        #expect(LayoutRule.holders("build.rs").map { [$0.directory, $0.member] } == [["", "build.rs"]])
    }
}
