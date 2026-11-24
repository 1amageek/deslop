# deslop

A CLI that prevents common structural mistakes in code, by the rule **deep
modules, narrow interfaces**. Its lints run on a language-neutral model of a
codebase; a frontend per language builds that model. This package ships the
lints, the model contract, and a Swift frontend. The lints' definitions began
as those of [deslop-please](https://github.com/deterministic-machines/deslop-please)
0.1.3; this project owns them now and is not compatible with it.

## 1. Requirements

| ID | Requirement |
|---|---|
| R1 | deslop detects what a general linter cannot: mistakes seen only across files, through what code refers to. What one file's syntax shows (naming, `try?`, formatting) is a general linter's, such as swift-format's, and no lint here repeats it. |
| R2 | The lints read only the language-neutral model (§2). No lint knows a language, a file extension, or a toolchain. Their definitions are §3 and the tests that state them. |
| R3 | The model has a versioned JSON form. Any frontend, in any language, can produce it; `deslop check --model <file>` lints it. |
| R4 | The Swift frontend (§4) builds the model of a SwiftPM package, or of an Xcode project or workspace, from its description, the compiler's IndexStore and the source text. |
| R5 | The CLI (§5) works as a lint: exit 0 when clean, 1 when it reports, 2 when it cannot run. An allowlist suppresses existing debt; new diagnostics still fail. |
| R6 | Failures are explicit. A model that breaks §2's invariants, a missing index, a missing libIndexStore or a failed build is a typed error with exit 2, never an empty or partial model reported as clean. |

## 2. Model contract (`DeslopModel`)

The model is the single source of truth for the lints. JSON form: `format: "deslop-model"`, `version: 1`.

| Part | Content |
|---|---|
| `language` | `name`, and `pathSeparator`: what joins a module's and an item's names in reports (`::` for Rust, `.` for Swift). |
| `nodes` | The hierarchy: one `workspace` root, `package` nodes (a crate, a Swift target), `module` nodes inside them. Each has `name`, `kind`, `parent`, `test`. A node's parent precedes it. |
| `files` | `path` (relative, `/`-separated), `module`, `test`, `lines` (every line, blank and comment lines too), `rank` (where a reader starts a module: 0 its root file, 1 the file that declares a directory, 2 any other, 3 an example), `declares` (the directory whose members the file declares, if any). |
| `items` | `name` (as its module writes it, joined by `pathSeparator`), `owner` (the module it is written in), `module` (the module it is, for a module item), `file`, `kind` (`module`, `type`, `impl`, `function`, `field`, `variant`, `constant`, `other`), `parent` (what it is written for), `implementsInterface` (a function that implements a trait or protocol requirement, or overrides), `takesSelf` (works on an instance), `holdsNothing` (a marker field), `inherits` (for a type, the types whose implementation it inherits and extends, such as a superclass; conformance to an interface is not inheritance). |
| `references` | `file`, `line`, `from` (module it is written in), `holder` (innermost item whose definition holds it, if any), `item`, `copies` (the code only reads the value; for a lent accessor's call, only reads what it lends), `test`. |
| `wrappers` | Functions that add nothing: `forwarder` (`target`, `fields` of `self` it calls on) or `accessor` (`lent`, `copied`, `toRead`). |

Invariants, checked when a model is decoded (violations are `ModelError`):

1. Every index refers to an existing node, file or item.
2. Exactly one root, the first node, of kind `workspace`; no other node is a workspace, and every other node's parent precedes it.
3. A package is inside the workspace or a package; a module is inside a package or a module. No two children of one node share a kind and a name.
4. Item parent chains end; no chain of forwarders loops; a function has at most one wrapper entry. Only a type inherits, only from types, and no chain of inheritance loops.
5. `pathSeparator` is not empty. A file's path is relative and not empty, its `lines` 0 or more, its `rank` 0 to 3; a reference's line is 1 or more.
6. `version` is 1 and `format` is `deslop-model`.

## 3. Lint contracts (`DeslopCore`)

Constants: `HELD_IN_MIND = 7`, `MOST_MEMBERS = 15`, `MOST_LINES = 2000`, `BREAK_EVEN = 1`.
Definitions:

- **Thing**: the item at the top of a parent chain when it is a non-test `type`, `function` or `constant`. Its home is that item's owner.
- **Use**: a non-test reference not held by a wrapper, seen through wrappers (a forwarder's chain to its target, plus reads of the fields it calls on; an accessor's fields, lent ones read only where the reference only reads).
- **Tangle**: a strongly connected set of two or more things.

| Lint | Reports |
|---|---|
| `module-cycle` | Sibling modules whose code names each other's items in a circle. Children of different packages, or a module and its descendants, make no cycle. |
| `tangle` | A tangle written in more than one module, or of more than 7 things. |
| `field-leak` | A field of a type that keeps at least one field to itself and has a non-wrapper method taking `self` that uses its fields, when an outsider uses that field other than by reading its value. Insiders are the type, the things of its tangle, and the types that inherit it (`inherits`, through any number of steps): how a type is extended by inheritance is its developers' choice, which no lint constrains. |
| `shallow-module` | A package or a non-test module with child modules that shows more than 7 working functions, hides no more than it shows, and has a list (of things, or of one thing's functions) longer than 7. |
| `wide-directory` | A directory holding more than 15 source files and directories. |
| `long-file` | A file of more than 2000 lines. |

Diagnostics are sorted by lint, then key. The allowlist is one `<lint> <key>` per line; an entry for a circle also allows every circle whose members are among its own.

## 4. Swift frontend (`DeslopSwift`)

| Model | Swift |
|---|---|
| package node | a Swift target of the root package; test targets are test nodes |
| module node | a directory below a target's root (a component directory) |
| file | each `.swift` source of each Swift target, as `swift package describe` lists it; files of test and plugin targets count for layout only, with no items or references |
| `type` | struct, class, actor, enum, protocol, typealias, associated type; a nested type is named after its outer type (`Outer.Inner`) but is a thing of its own, as a Rust type in a module is |
| `field` | a stored instance property (with or without observers or a property wrapper), each name of a tuple pattern included; its type is the one written, or the one its initial value gives: a literal's (`0`, `-1`, `"a"`), or the type it constructs (`Inner()`, `[Int]()`) when the index names a type there |
| `function` | function, method, initializer, deinitializer, subscript, computed property |
| `constant` | a global variable, or a stored static property |
| `variant` | an enum case |
| `parent` | the type a member is written for, wherever its extension is |
| `implementsInterface` | a member that overrides; a deinitializer; a function that meets a requirement of a protocol its type conforms to, wherever the conformance is declared and through any refinement: the requirement has its name and, as their USRs demangled by the Swift runtime write what follows the name, its signature; or, when the requirement's signature names `Self` or an associated type, it is the only function of that name in its type. Requirements come from the workspace and from the records the index keeps of the system modules it imports |
| `takesSelf` | an instance method, computed instance property or instance subscript |
| `inherits` | the superclasses a class names, as the index records them |
| `holdsNothing` | a field of type `Void` or `()` |
| reference | a non-implicit index occurrence that names an item; `holder` is the innermost declaration around it; an extension's header has none |
| `copies` (field, or lent accessor) | write role → no; assigned or `&`-passed → no; reached through a projected value (`$model.name`, a `Binding` that writes it) → no; named by a key path → what is done where the key path's value goes, as below; a cast (`as`, `as!`, `as?`) or a fallback (`??`) hands it on, and what is done with the result is done with it. Otherwise, of a field whose type is a value type (a struct or enum as the index names it, an array, dictionary or literal type, or an optional or tuple of those) → yes: what is reached or subscripted on a value reads it, and the index marks a mutating use as a write. Of any other field: subscripted → no; `utf8`/`utf16`/`unicodeScalars` reached on it → only if its type is plain data; another member reached on it → only if its type is a scalar; any other use of its value, an argument label included → yes |
| forwarder | a non-witness function whose body is one call to another workspace function, on a parameter, `self` or a field path of `self`, passing exactly the function's own parameters |
| accessor | a non-witness instance computed property, subscript or method whose body names only fields of its own type, computes nothing, and whose signature writes each field's declared type; fields are lent, `toRead` unless it is a method that writes. An initializer of that shape, which only assigns parameters to fields, is an accessor whose fields are copied: like a Rust struct literal it adds nothing |
| `rank` / `declares` | `main.swift` or `<Target>.swift` at a target root: 0; `<Dir>.swift` in `<Dir>/`: 1; names compare in any case |

The index comes from `swift build --enable-index-store` in a scratch path of its own (`.build/deslop`), so the package's own builds are untouched; libIndexStore is loaded from the toolchain of the `swift` that builds (`DESLOP_LIBINDEXSTORE` names another). Only the latest unit of each indexed source file is read. An indexed source with no unit, or written after its unit was (an index older than the text, as `--skip-build` can meet), is an error. A file that starts with a byte order mark has its first line's columns counted as the index counts them. A reference names what the active build configuration compiles: code under an inactive `#if` is not seen.

A key path is followed from where it is written to where its value goes; what is done there is done with the field it names:

| Where the value goes | What it does |
|---|---|
| applied in a `[keyPath:]` subscript | what is done there with the field; a member reached on it → no |
| passed to a function, subscript, initializer, attribute, macro or operator | no, when the signature of what it is passed to declares a `WritableKeyPath` or `ReferenceWritableKeyPath`, or is not one the index names; else yes. The signature is the index's USR of it, demangled by the Swift runtime: a mangling writes a repeated word as a back reference, so its text cannot be searched |
| bound or assigned to a local | what each use that may see it does: those after it in the code that declares the local, any in a loop around the assignment; a tuple target, each of its elements |
| iterated by `for` | what each use of the loop's name does |
| stored in, assigned to or returned from a property, function or subscript the index names | yes, when its USR declares no writable key path; else what every place in the workspace that names it does with its value, those the index marks as writes included: it marks applying a key path to mutate as a write of what holds it. A use that leads back to one being followed adds nothing |
| returned from a local function or closure | what is done with what it returns; a closure whose written result declares no writable key path → yes |
| in an array, dictionary, tuple or parentheses, a branch of `?:`, `if` or `switch`, either side of `??`, or cast to a writable key path | what is done with the whole |
| cast to another type, compared or combined by operators whose signatures declare no writable key path, matched by a `case`, interpolated, discarded | yes |
| what holds it, assigned to | nothing is done with it |
| anywhere else | no: it may be written through |

### 4.1 Xcode projects

The same model, from an Xcode project or workspace:

| Model | Xcode |
|---|---|
| package node | a native target of the project (or of each project of the workspace), and a module compiled from a local package below the root; unit-test and UI-test targets are test nodes |
| a target's root | its first file-system-synchronized folder; for a target of listed files, the directory all its compiled files share |
| module node | a directory below a target's root; a file outside its target's root is the target's own |
| file | each Swift file a built target compiled, as the index records it; for a target not built (a test target), the Swift files the project lists for it, which count for layout only |

Which files a target compiles is told by the index's units (module name and main file), not by the project's file lists, so file-system-synchronized folders and their exceptions are honoured as the build honours them. Files under the derived data directory (generated sources, package checkouts) are not the project's.

The build: every scheme `xcodebuild -list` names that the project or workspace defines (a scheme file under it, or a scheme named after one of its targets), or those `--scheme` names, is built in turn into one derived data directory, `.build/deslop/xcode`, with `COMPILER_INDEX_STORE_ENABLE=YES`, code signing off, and only the running Mac's architecture. A scheme builds for macOS when every target in it supports macOS, else for the iOS Simulator, else for the one simulator they all support; `--destination` names another. `xcodebuild` and libIndexStore are Xcode's: `TOOLCHAINS` is not passed on, unless `--toolchain` names one. A failed build, a scheme that cannot build, or a non-test target that no built scheme compiled (when no `--scheme` is given) is an error.

## 5. CLI (`deslop`)

```
deslop [<target-or-module>] [--allow <path> | --update-allow <path>] [--package-path <dir>] [--skip-build] [<xcode options>]
deslop model [--package-path <dir>] [--skip-build] [--output <path>] [<xcode options>]
deslop check --model <path> [<package-or-module>] [--allow <path> | --update-allow <path>]

xcode options: [--project <path> | --workspace <path>] [--scheme <name>]... [--destination <spec>] [--toolchain <id>]
```

The directory is a SwiftPM package when it has a `Package.swift` and neither `--project` nor `--workspace` is given; else the one workspace, or else the one project, at its top level. None, or more than one, is an error that names what to pass.

A run scoped to a target or module judges only its scope: `--allow` counts an entry as fixed only when nothing reports it anywhere, and `--update-allow` keeps the existing entries that still allow something reported outside the scope.

Output is a compiler-style report; the last line is `deslop: ok` or `deslop: N errors, well done!`. Color: `DESLOP_COLOR=always|never`, then `NO_COLOR`, then whether stdout is a terminal.

## 6. Acceptance criteria

| ID | Criterion | Evidence |
|---|---|---|
| A1 | Each lint reports what §3 defines, and only that, on models of every shape §2 allows; a picture of any length is drawn. | `DeslopCoreTests`, on Rust-flavored models (separator `::`), which also shows no lint knows Swift |
| A2 | The JSON model round-trips and invalid models are rejected with the broken invariant named. | `DeslopModelTests` |
| A3 | The Swift frontend reports a field leak (and its getter variant), its fix, a module cycle and its fix, a tangle across modules, a shallow module, a clean package, and test code left out; and types inferred from initial values, tuple patterns, files with a byte order mark, and a stale index as §4 says. | `DeslopSwiftTests` end-to-end on `Fixtures/` and on packages the tests write |
| A6 | The Xcode frontend builds an Xcode project with a file-system-synchronized target and a test target, reports the same lints on it as on a package, leaves test code out, and fails explicitly on a build error or a target no scheme built. | `DeslopSwiftTests` on `Fixtures/Xcode` |
| A4 | The CLI's exit codes, allowlist (CRLF included, fixed entries counted across scopes) and `check --model` behave as §5 says. | `DeslopTests`, `DeslopCoreTests` |
| A5 | `deslop` runs clean on its own source with no allowlist. | running it on this package |

No contract here is a state machine or concurrent protocol: the lints are pure functions of the model, and the CLI runs one sequential pipeline. Their contracts are checked by the tests above rather than by TLA+ or Lean.
