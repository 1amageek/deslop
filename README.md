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
deslop --scheme App                   # an Xcode project or workspace: only scheme App
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

It checks a SwiftPM package, or an Xcode project or workspace: in a directory
with a `Package.swift` it builds the package; otherwise it builds every scheme
of the workspace or project there with Xcode's toolchain, for macOS or else the
iOS Simulator (`--scheme`, `--destination`, `--toolchain` and `--project` /
`--workspace` choose otherwise). Its builds go to `.build/deslop`, apart from
your own. In Swift, a target is a package and each directory below a target's
root is a module. See [SPEC.md](SPEC.md) for the model contract, the lints' definitions,
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

Requires macOS 15 or later, or Linux, and a Swift toolchain; tested with
Swift 6.4.1 on macOS and in the `swift:6.4.1` Linux image. Xcode projects
need macOS and Xcode.

With [Mint](https://github.com/yonaskolb/Mint):

```bash
mint install 1amageek/deslop@1.0.0   # links ~/.mint/bin/deslop
```

Or, in a `Mintfile`, add the line `1amageek/deslop@1.0.0` and run
`mint run deslop`.

From source:

```bash
git clone --branch 1.0.0 --depth 1 https://github.com/1amageek/deslop.git
cd deslop
swift build -c release --product deslop
cp .build/release/deslop ~/.local/bin/   # or anywhere on your PATH
```

## What it checks

`deslop` reads the index the compiler writes as it builds, so the code must
build, and it checks what that build compiles: code in an inactive `#if`
branch, or for another platform, is not checked. A project that needs setup
before it builds, such as `pod install`, must be set up first; when the build
fails, `deslop` says why and exits with `2`.

An allowlist holds one `<lint> <key>` per line, as `--update-allow` writes it.
An entry for a circle also allows every circle whose members are among its
own. When entries no longer allow anything, `deslop` counts them and suggests
`--update-allow` to drop them, so the list can only shrink.

## Use in CI

```yaml
jobs:
  deslop:
    runs-on: ubuntu-latest
    container: swift:6.4.1
    steps:
      - uses: actions/checkout@v4
      - run: |
          git clone --branch 1.0.0 --depth 1 https://github.com/1amageek/deslop.git /tmp/deslop
          swift build -c release --product deslop --package-path /tmp/deslop
          /tmp/deslop/.build/release/deslop --allow .deslop.allow
```

## Use the libraries

The model, the lints and the Swift frontend are libraries too: a frontend for
another language writes a `DeslopModel` and lints it with `DeslopCore`, or
writes the model's JSON for `deslop check`.

```swift
.package(url: "https://github.com/1amageek/deslop.git", from: "1.0.0"),
```

## Test

```bash
swift test
```

## License

MIT. The lints' definitions began as those of deslop-please, also MIT; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
