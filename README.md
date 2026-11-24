# swift-deslop

An opinionated architectural linter for Swift: **deep** modules, **narrow**
interfaces. It follows [deslop-please](https://github.com/deterministic-machines/deslop-please)
and *A Philosophy of Software Design*, and runs its six lints on a
language-neutral model, so any language's frontend can use them.

```bash
swift-deslop                       # lint the Swift package in the current directory
swift-deslop MyTarget.Store        # only what concerns one target or module
swift-deslop --update-allow .swift-deslop.allow   # record existing debt
swift-deslop --allow .swift-deslop.allow          # new errors still fail
swift-deslop model --output model.json            # the package's model, as JSON
swift-deslop check --model model.json             # lint any frontend's model
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
swift-deslop  command line
```

## Add to your `AGENTS.md`

```markdown
- Run `swift-deslop` to check for sloppy code structure.
- Errors flagged by `swift-deslop` must be fixed from first principles, not by mechanical moves that hide them.
```

## Build and test

```bash
swift build -c release --product swift-deslop
swift test
```
