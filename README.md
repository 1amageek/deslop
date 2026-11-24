# deslop

A CLI that prevents common structural mistakes: **deep** modules, **narrow**
interfaces, after *A Philosophy of Software Design*. It detects what a general
linter cannot, mistakes seen only across files through what code refers to,
and leaves what one file's syntax shows to linters such as swift-format. Its
lints run on a language-neutral model, so any language's frontend can use them.
Their definitions began as those of
[deslop-please](https://github.com/deterministic-machines/deslop-please).

```bash
deslop                                # lint the Swift package in the current directory
deslop MyTarget.Store                 # only what concerns one target or module
deslop --update-allow .deslop.allow   # record existing debt
deslop --allow .deslop.allow          # new errors still fail
deslop model --output model.json      # the package's model, as JSON
deslop check --model model.json       # lint any frontend's model
```

Exit status: `0` nothing reported, `1` reports, `2` cannot run.

| Lint | Reports |
|---|---|
| `module-cycle` | sibling modules (component directories) that use each other in a circle |
| `tangle` | things that know each other in a circle, across modules or more than 7 of them |
| `field-leak` | a stored field that code outside its type writes, subscripts, or reaches into |
| `shallow-module` | a target or module that shows more than 7 functions, no fewer than it hides |
| `wide-directory` | a directory of more than 15 source files and directories |
| `long-file` | a file of more than 2,000 lines |

In Swift, a target is a package and each directory below a target's root is a
module. See [SPEC.md](SPEC.md) for the model contract, the lints' definitions,
and how Swift maps onto them.

## Layout

```text
DeslopModel   language-neutral model and its JSON contract
DeslopCore    graph, lints, allowlist, report         (reads DeslopModel only)
DeslopSwift   Swift frontend: SwiftPM + IndexStore + swift-syntax → model
deslop        command line
```

## Add to your `AGENTS.md`

```markdown
- Run `deslop` to check for sloppy code structure.
- Errors flagged by `deslop` must be fixed from first principles, not by mechanical moves that hide them.
```

## Install

Requires macOS 15 or later and a Swift toolchain; tested with Swift 6.4.1.

```bash
git clone https://github.com/1amageek/deslop.git
cd deslop
swift build -c release --product deslop
cp .build/release/deslop /usr/local/bin/   # or anywhere on your PATH
```

## Test

```bash
swift test
```

## License

MIT. The lints' definitions began as those of deslop-please, also MIT; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
