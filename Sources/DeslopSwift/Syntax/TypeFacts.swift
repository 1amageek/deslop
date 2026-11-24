/// What a declared type, written as its tokens, holds.
enum TypeFacts {
    /// Types that hold one number, truth value or character: nothing can be
    /// done to one but read or overwrite it.
    static let scalars: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64", "Int128",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128",
        "Float", "Float16", "Float32", "Float64", "Float80", "Double", "CGFloat",
        "Bool", "Character",
    ]

    /// Whether `tokens` write a scalar type: `Int`, `Swift.Int`.
    static func isScalar(_ tokens: [String]) -> Bool {
        if tokens.count == 1 { return scalars.contains(tokens[0]) }
        if tokens.count == 3, tokens[0] == "Swift", tokens[1] == "." { return scalars.contains(tokens[2]) }
        return false
    }

    /// Whether `tokens` write plain data: scalars and text, in arrays, sets,
    /// optionals or tuples, nothing inside but values.
    static func isData(_ tokens: [String]) -> Bool {
        let holders: Set<String> = ["String", "Substring", "Array", "Set", "Optional", "Swift"]
        let punctuation: Set<String> = ["[", "]", "?", "<", ">", ",", "(", ")", "."]
        return !tokens.isEmpty && tokens.allSatisfy {
            scalars.contains($0) || holders.contains($0) || punctuation.contains($0)
        }
    }

    /// Whether `tokens` write a type that holds nothing: `Void`, `()`.
    static func holdsNothing(_ tokens: [String]) -> Bool {
        tokens == ["Void"] || tokens == ["(", ")"] || tokens == ["Swift", ".", "Void"]
    }
}
