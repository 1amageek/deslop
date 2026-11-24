/// What a declaration's USR, demangled, says of what it takes and returns:
/// of `main.pass(_: Swift.KeyPath<main.Q, [Swift.Int]>, flag: Swift.Bool) -> Swift.KeyPath<main.Q, [Swift.Int]>`,
/// two parameters and a result.
struct Signature: Sendable {
    /// A parameter: its label, `nil` for none, and its type's tokens.
    struct Parameter: Sendable, Equatable {
        let label: String?
        let type: [String]
    }

    /// What it declares of key paths.
    let keyPaths: KeyPathSignature
    /// Its parameters, and the tokens of its result's type; `nil` where the
    /// text writes none this reads, as for a stored property's type.
    let parameters: [Parameter]?
    let result: [String]?

    init(usr: String) {
        keyPaths = KeyPathSignature(usr: usr)
        let read = Demangled.text(ofUSR: usr).flatMap(Signature.read)
        parameters = read?.parameters
        result = read?.result
    }

    /// The signature the demangled `text` writes.
    init(text: String) {
        keyPaths = KeyPathSignature(text: text)
        let read = Signature.read(text)
        parameters = read?.parameters
        result = read?.result
    }

    /// Whether what is passed as the `index`th of `labels`, the labels of a
    /// call's arguments in order, may come back in what the call returns:
    /// the result's type names the type of the parameter it is passed for,
    /// as `id<A>(A) -> A` hands back its argument. For a closure passed for a
    /// function's parameter, what may come back is what the closure returns:
    /// the result's type names the parameter's result, as `map` hands back
    /// what its closure returns. `true` where the signature or the parameter
    /// is not known.
    func mayReturn(argument index: Int, of labels: [String?], closure: Bool) -> Bool {
        guard let parameters, let result, let parameter = Signature.parameter(for: index, of: labels, in: parameters) else {
            return true
        }
        return Signature.mayReturn(parameter, in: result, closure: closure)
    }

    /// Whether what a trailing closure returns may come back in what the
    /// call returns: it is passed for the last parameter of a function type.
    func mayReturnFromTrailingClosure() -> Bool {
        guard let parameters, let result,
              let parameter = parameters.last(where: { Signature.topLevel("->", in: $0.type) != nil }) else { return true }
        return Signature.mayReturn(parameter, in: result, closure: true)
    }

    private static func mayReturn(_ parameter: Parameter, in result: [String], closure: Bool) -> Bool {
        var type = parameter.type.filter { $0 != "..." }
        if closure, let arrow = topLevel("->", in: type) {
            type = Array(type[(arrow + 1)...])
        }
        guard !type.isEmpty, result.count >= type.count else { return false }
        return (0...(result.count - type.count)).contains { Array(result[$0..<$0 + type.count]) == type }
    }

    /// The parameter the `index`th argument is passed for: arguments go to
    /// parameters in order, each to the next of its label, those with
    /// defaults left out; a variadic parameter takes the arguments after it
    /// that have no label.
    private static func parameter(for index: Int, of labels: [String?], in parameters: [Parameter]) -> Parameter? {
        var at = 0
        var variadic: Int?
        for (argument, label) in labels.enumerated() {
            if label == nil, let taking = variadic {
                if argument == index { return parameters[taking] }
                continue
            }
            variadic = nil
            while at < parameters.count, parameters[at].label != label { at += 1 }
            guard at < parameters.count else { return nil }
            if parameters[at].type.last == "..." { variadic = at }
            if argument == index { return parameters[at] }
            at += 1
        }
        return nil
    }

    /// The parameters and result `text` writes: the first parenthesized
    /// list outside brackets, after any extension context, and what follows
    /// its `->`. A property of a function type is read as that type.
    private static func read(_ text: String) -> (parameters: [Parameter], result: [String])? {
        var tokens = tokenize(text)
        // `(extension in Lib):Swift.Array.first() -> A?`
        while tokens.count >= 2, tokens[0] == "(", tokens[1] == "extension",
              let close = tokens.firstIndex(of: ")"), close + 1 < tokens.count, tokens[close + 1] == ":" {
            tokens.removeFirst(close + 2)
        }
        var depth = 0
        var open: Int?
        for (index, token) in tokens.enumerated() {
            if token == "(", depth == 0 { open = index; break }
            if token == "<" || token == "[" { depth += 1 }
            if token == ">" || token == "]" { depth -= 1 }
        }
        guard let open else { return nil }
        return function(Array(tokens[open...]))
    }

    /// The parameters and result of the function type `tokens` starts with.
    /// An enum case, `Swift.Optional.some(A?.Type) -> (A) -> A?`, first takes
    /// its type: the function it then is is read.
    private static func function(_ tokens: [String]) -> (parameters: [Parameter], result: [String])? {
        guard tokens.first == "(", let close = matching(0, in: tokens) else { return nil }
        let rest = Array(tokens[(close + 1)...])
        guard let arrow = topLevel("->", in: rest) else { return nil }
        let inside = Array(tokens[1..<close])
        let result = Array(rest[(arrow + 1)...])
        if inside.suffix(2) == [".", "Type"] || inside.last?.hasSuffix(".Type") == true,
           topLevel(",", in: inside) == nil, result.first == "(", let curried = function(result) {
            return curried
        }
        let parameters = split(inside).map { parameter -> Parameter in
            var type = parameter
            var label: String?
            if type.count >= 2, type[1] == ":", type[0].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                label = type[0] == "_" ? nil : type[0]
                type.removeFirst(2)
            }
            type.removeAll { $0 == "inout" || $0 == "__owned" || $0 == "__shared" || $0 == "@escaping" || $0 == "sending" }
            return Parameter(label: label, type: type)
        }
        return (parameters, result)
    }

    /// The tokens of a demangled text: names with their dots, `->`, `...`,
    /// and each other mark; spaces between them dropped.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var name = ""
        let characters = Array(text)
        var index = 0
        func flush() {
            if !name.isEmpty { tokens.append(name); name = "" }
        }
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" || character == "@" || character == "$" {
                name.append(character)
            } else if character == ".", index + 2 < characters.count, characters[index + 1] == ".", characters[index + 2] == "." {
                flush()
                tokens.append("...")
                index += 2
            } else if character == ".", !name.isEmpty {
                name.append(character)
            } else if character == "-", index + 1 < characters.count, characters[index + 1] == ">" {
                flush()
                tokens.append("->")
                index += 1
            } else {
                flush()
                if !character.isWhitespace { tokens.append(String(character)) }
            }
            index += 1
        }
        flush()
        return tokens
    }

    /// The index of the bracket that closes the one at `open`.
    private static func matching(_ open: Int, in tokens: [String]) -> Int? {
        var depth = 0
        for index in open..<tokens.count {
            if "([<".contains(tokens[index]) && tokens[index].count == 1 { depth += 1 }
            if ")]>".contains(tokens[index]) && tokens[index].count == 1 { depth -= 1 }
            if depth == 0 { return index }
        }
        return nil
    }

    /// The first `token` of `tokens` outside any brackets.
    static func topLevel(_ token: String, in tokens: [String]) -> Int? {
        var depth = 0
        for (index, next) in tokens.enumerated() {
            if next == token, depth == 0 { return index }
            if next == "(" || next == "[" || next == "<" { depth += 1 }
            if next == ")" || next == "]" || next == ">" { depth -= 1 }
        }
        return nil
    }

    /// `tokens` split at their commas outside brackets.
    private static func split(_ tokens: [String]) -> [[String]] {
        guard !tokens.isEmpty else { return [] }
        var parts: [[String]] = [[]]
        var depth = 0
        for token in tokens {
            if token == ",", depth == 0 {
                parts.append([])
                continue
            }
            if token == "(" || token == "[" || token == "<" { depth += 1 }
            if token == ")" || token == "]" || token == ">" { depth -= 1 }
            parts[parts.count - 1].append(token)
        }
        return parts
    }
}
