/// Reads the command line.
enum InvocationParser {
    static let usage = """
        usage: swift-deslop [<target-or-module>] [--allow <path> | --update-allow <path>]
                            [--package-path <dir>] [--skip-build]
               swift-deslop model [--package-path <dir>] [--skip-build] [--output <path>]
               swift-deslop check --model <path> [<package-or-module>] [--allow <path> | --update-allow <path>]

        Runs architectural lints (module-cycle, tangle, field-leak, shallow-module,
        wide-directory, long-file) on a Swift package, or on the language-neutral
        model of any codebase.

        commands:
          (none)                  lint the Swift package in the current directory
          model                   write the package's model as JSON
          check                   lint a model file written by any frontend

        options:
          <target-or-module>      check only one target or module (e.g. MyTarget.Store)
          --allow <path>          suppress listed existing debt; new errors still fail
          --update-allow <path>   write current diagnostics to <path>
          --package-path <dir>    the package's root (default: the current directory)
          --skip-build            read the index of the last build instead of building
          --model <path>          the model file to check
          --output <path>         where to write the model (default: standard output)

        """

    static func parse(_ arguments: [String]) throws(CommandError) -> Invocation {
        if arguments.count == 1, ["-h", "--help", "help"].contains(arguments[0]) {
            return .help
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
        let valued: Set<String> = ["--allow", "--update-allow", "--package-path", "--model", "--output"]
        while let word = words.first {
            words = words.dropFirst()
            if valued.contains(word) {
                guard let value = words.first, values[word] == nil else {
                    throw .usage("`\(word)` needs one value")
                }
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
            return .exportModel(
                packagePath: values["--package-path"] ?? ".",
                buildsIndex: !flags.contains("--skip-build"),
                output: values["--output"]
            )
        case "check":
            try reject(["--package-path", "--skip-build", "--output"])
            guard let model = values["--model"] else { throw .usage("`check` needs `--model <path>`") }
            return .checkModel(modelPath: model, reporting: reporting)
        default:
            try reject(["--model", "--output"])
            return .lintPackage(
                packagePath: values["--package-path"] ?? ".",
                buildsIndex: !flags.contains("--skip-build"),
                reporting: reporting
            )
        }
    }
}
