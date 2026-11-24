/// Reads the command line.
enum InvocationParser {
    static let usage = """
        usage: deslop [<target-or-module>] [--allow <path> | --update-allow <path>]
                      [--package-path <dir>] [--skip-build] [<xcode options>]
               deslop model [--package-path <dir>] [--skip-build] [--output <path>] [<xcode options>]
               deslop check --model <path> [<package-or-module>] [--allow <path> | --update-allow <path>]

        xcode options: [--project <path> | --workspace <path>] [--scheme <name>]...
                       [--destination <spec>] [--toolchain <identifier>]

        Runs architectural lints (module-cycle, tangle, field-leak, shallow-module,
        wide-directory, long-file) on a Swift package, or on the language-neutral
        model of any codebase.

        commands:
          (none)                  lint the Swift package, or else the Xcode workspace or
                                  project, in the current directory
          model                   write the package's model as JSON
          check                   lint a model file written by any frontend

        options:
          <target-or-module>      check only one target or module (e.g. MyTarget.Store)
          --allow <path>          suppress listed existing debt; new errors still fail
          --update-allow <path>   write current diagnostics to <path>
          --package-path <dir>    the package's or project's directory (default: the current one)
          --skip-build            read the index of the last build instead of building
          --model <path>          the model file to check
          --output <path>         where to write the model (default: standard output)
          --project <path>        the Xcode project to check, when the directory holds several
          --workspace <path>      the Xcode workspace to check
          --scheme <name>         a scheme to build and check; repeat for more (default: all
                                  schemes the project or workspace defines)
          --destination <spec>    where xcodebuild builds (default: macOS, else iOS Simulator)
          --toolchain <id>        the toolchain xcodebuild builds with (default: Xcode's)
          --version               print the version

        """

    static func parse(_ arguments: [String]) throws(CommandError) -> Invocation {
        if arguments.contains(where: { ["-h", "--help"].contains($0) }) || arguments == ["help"] {
            return .help
        }
        if arguments.contains("--version") {
            return .version
        }
        var words = arguments[...]
        let command: String?
        if let first = words.first, first == "model" || first == "check" {
            command = first
            words = words.dropFirst()
        } else {
            command = nil
        }
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var positional: [String] = []
        let valued: Set<String> = [
            "--allow", "--update-allow", "--package-path", "--model", "--output",
            "--project", "--workspace", "--destination", "--toolchain",
        ]
        var schemes: [String] = []
        while let word = words.first {
            words = words.dropFirst()
            if word == "--scheme" {
                guard let value = words.first else { throw .usage("`--scheme` needs one value") }
                schemes.append(value)
                words = words.dropFirst()
            } else if valued.contains(word) {
                guard values[word] == nil else { throw .usage("`\(word)` is given more than once") }
                guard let value = words.first else { throw .usage("`\(word)` needs one value") }
                values[word] = value
                words = words.dropFirst()
            } else if word == "--skip-build" {
                flags.insert(word)
            } else if word.hasPrefix("-") {
                throw .usage("unknown option `\(word)`")
            } else {
                positional.append(word)
            }
        }
        guard positional.count <= 1 else { throw .usage("at most one target or module") }
        if values["--allow"] != nil && values["--update-allow"] != nil {
            throw .usage("`--allow` and `--update-allow` exclude each other")
        }
        if values["--project"] != nil && values["--workspace"] != nil {
            throw .usage("`--project` and `--workspace` exclude each other")
        }
        let source = Invocation.Source(
            path: values["--package-path"] ?? ".",
            buildsIndex: !flags.contains("--skip-build"),
            project: values["--project"],
            workspace: values["--workspace"],
            schemes: schemes,
            destination: values["--destination"],
            toolchain: values["--toolchain"]
        )
        let xcodeOptions = ["--project", "--workspace", "--destination", "--toolchain"]
        let reporting = Invocation.Reporting(
            scope: positional.first,
            allow: values["--allow"],
            updateAllow: values["--update-allow"]
        )
        func reject(_ options: [String]) throws(CommandError) {
            for option in options where values[option] != nil || flags.contains(option) {
                throw .usage("`\(option)` does not apply here")
            }
        }
        switch command {
        case "model":
            try reject(["--allow", "--update-allow", "--model"])
            guard positional.isEmpty else { throw .usage("`model` takes no target or module") }
            return .exportModel(source: source, output: values["--output"])
        case "check":
            try reject(["--package-path", "--skip-build", "--output"] + xcodeOptions)
            guard schemes.isEmpty else { throw .usage("`--scheme` does not apply here") }
            guard let model = values["--model"] else { throw .usage("`check` needs `--model <path>`") }
            return .checkModel(modelPath: model, reporting: reporting)
        default:
            try reject(["--model", "--output"])
            return .lintPackage(source: source, reporting: reporting)
        }
    }
}
