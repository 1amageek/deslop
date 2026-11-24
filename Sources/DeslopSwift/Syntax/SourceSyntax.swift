import SwiftParser
import SwiftSyntax

/// A Swift source file's syntax, read for what the index leaves out: which
/// declarations hold a place, whether a property is stored, what code does
/// with a name it writes, and what a function's body does.
final class SourceSyntax {
    private let tree: SourceFileSyntax
    private let converter: SourceLocationConverter
    private var tokens: [SourcePosition: TokenSyntax] = [:]
    let declarations: [SourcePosition: Declaration]
    /// Every declaration's range and name, widest first among those that
    /// start together, by start.
    private let holders: [(range: Range<Int>, name: SourcePosition)]

    /// UTF-8 bytes of a byte order mark the file started with, which the
    /// index's columns count and the text, read without it, does not.
    private let byteOrderMark: Int

    init(text: String, fileName: String, byteOrderMark: Int = 0) {
        tree = Parser.parse(source: text)
        let converter = SourceLocationConverter(fileName: fileName, tree: tree)
        self.converter = converter
        self.byteOrderMark = byteOrderMark
        let declarations = DeclarationCollector.declarations(in: tree) { token in
            SourceSyntax.position(token, converter: converter, byteOrderMark: byteOrderMark)
        }
        self.declarations = declarations
        holders = declarations
            .map { (range: $0.value.range, name: $0.key) }
            .sorted { $0.range.lowerBound != $1.range.lowerBound
                ? $0.range.lowerBound < $1.range.lowerBound
                : $0.range.upperBound > $1.range.upperBound }
        for token in tree.tokens(viewMode: .sourceAccurate) {
            tokens[position(token)] = token
        }
    }

    func position(_ token: TokenSyntax) -> SourcePosition {
        SourceSyntax.position(token, converter: converter, byteOrderMark: byteOrderMark)
    }

    /// Where `token` starts, as the index writes places: its first line's
    /// columns count any byte order mark.
    private static func position(_ token: TokenSyntax, converter: SourceLocationConverter, byteOrderMark: Int) -> SourcePosition {
        let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
        let column = location.line == 1 ? location.column + byteOrderMark : location.column
        return SourcePosition(line: location.line, column: column)
    }

    /// The token the index names at `position`: the one that starts there,
    /// or a projected value's, `$name`, which the index places after its `$`.
    private func token(at position: SourcePosition) -> TokenSyntax? {
        if let token = tokens[position] { return token }
        guard position.column > 1,
              let projected = tokens[SourcePosition(line: position.line, column: position.column - 1)],
              projected.text.hasPrefix("$") else { return nil }
        return projected
    }

    /// The names of the declarations around `position`, innermost first.
    func holders(of position: SourcePosition) -> [SourcePosition] {
        guard let token = token(at: position) else { return [] }
        let offset = token.positionAfterSkippingLeadingTrivia.utf8Offset
        return holders
            .filter { $0.range.contains(offset) }
            .sorted { $0.range.count < $1.range.count }
            .map(\.name)
    }

    /// What the code does with the field or property it names at `position`.
    /// `facts` tells whether a member named at a position is a stored
    /// field, through which the place goes on: `queue.inner.items.count`
    /// reaches into `inner` as it does into `items`.
    func access(at position: SourcePosition, facts: NameFacts) -> Access {
        guard token(at: position) != nil else { return .reach }
        // A name that is no expression, such as an argument label of a
        // memberwise initializer, gives or takes the value whole.
        guard let place = place(at: position) else { return .copy }
        // `$model.name` makes a `Binding` through the projected value, which
        // writes what it names; the index marks it as a read only.
        if SourceSyntax.isProjected(place) { return .reach }
        return access(of: place, facts: facts)
    }

    /// What the code does with what the method it calls at `position` hands
    /// out, as `access(at:facts:)` reads a field: `queue.head().count`
    /// reaches into what `head()` lends. A method not called where it is
    /// named, but passed on, reaches.
    func callAccess(at position: SourcePosition, facts: NameFacts) -> Access {
        guard let place = place(at: position),
              let call = place.parent?.as(FunctionCallExprSyntax.self),
              call.calledExpression.id == place.id else { return .reach }
        return access(of: Syntax(call), facts: facts)
    }

    /// The expression that is the place named at `position`: `queue.head`
    /// for `head`, or `head` alone.
    private func place(at position: SourcePosition) -> Syntax? {
        guard let token = token(at: position), let reference = token.parent?.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        if let member = reference.parent?.as(MemberAccessExprSyntax.self), member.declName.id == reference.id {
            return Syntax(member)
        }
        return Syntax(reference)
    }

    /// What the code does with `place`, the expression that names a field.
    func access(of place: Syntax, facts: NameFacts) -> Access {
        var current = place
        while let parent = current.parent {
            if let chained = parent.as(OptionalChainingExprSyntax.self), chained.expression.id == current.id {
                current = parent
                continue
            }
            if let unwrapped = parent.as(ForceUnwrapExprSyntax.self), unwrapped.expression.id == current.id {
                current = parent
                continue
            }
            if let element = parent.as(LabeledExprSyntax.self), element.label == nil,
               let list = element.parent?.as(LabeledExprListSyntax.self), list.count == 1,
               let tuple = list.parent?.as(TupleExprSyntax.self) {
                current = Syntax(tuple)
                continue
            }
            if let member = parent.as(MemberAccessExprSyntax.self), member.base?.id == current.id {
                if facts.isField(position(member.declName.baseName)) {
                    current = parent
                    continue
                }
                return SourceSyntax.borrows.contains(member.declName.baseName.text) ? .borrow : .call
            }
            if let subscripted = parent.as(SubscriptCallExprSyntax.self), subscripted.calledExpression.id == current.id {
                return .subscripted
            }
            if let call = parent.as(FunctionCallExprSyntax.self), call.calledExpression.id == current.id {
                return .call
            }
            if parent.is(InOutExprSyntax.self) {
                return .reach
            }
            if parent.is(KeyPathPropertyComponentSyntax.self) {
                return KeyPathFlow(syntax: self, facts: facts).access(ofComponent: Syntax(parent))
            }
            if let list = parent.as(ExprListSyntax.self), let sequence = parent.parent, sequence.is(SequenceExprSyntax.self),
               SourceSyntax.passesOn(Array(list), current) {
                current = sequence
                continue
            }
            if let list = parent.as(ExprListSyntax.self), parent.parent?.is(SequenceExprSyntax.self) == true {
                let elements = Array(list)
                if let at = elements.firstIndex(where: { $0.id == current.id }), at + 1 < elements.count,
                   SourceSyntax.assigns(elements[at + 1]) {
                    return .reach
                }
            }
            return .copy
        }
        return .copy
    }

    /// Whether the operation of `elements`, an unfolded sequence of one
    /// operator, hands `operand` on as its own value: a cast (`as`, `as!`,
    /// `as?`) hands on its left side, a fallback (`??`) either side. What is
    /// reached on the result is reached on the operand.
    private static func passesOn(_ elements: [ExprSyntax], _ operand: Syntax) -> Bool {
        guard elements.count == 3 else { return false }
        let side = elements.firstIndex { $0.id == operand.id }
        if elements[1].is(UnresolvedAsExprSyntax.self) { return side == 0 }
        if let binary = elements[1].as(BinaryOperatorExprSyntax.self), binary.operator.text == "??" {
            return side == 0 || side == 2
        }
        return false
    }

    /// What code does with the value named at `position`, a property's or
    /// a function's that holds or hands out a key path: what is done where
    /// the value goes, as `KeyPathFlow` follows it.
    func keyPathUse(at position: SourcePosition, facts: NameFacts) -> Access {
        guard let place = place(at: position) else { return .reach }
        return KeyPathFlow(syntax: self, facts: facts).use(of: place)
    }

    /// Members that lend a view of a value to read it, as Rust's `as_bytes`
    /// borrows: they hand out nothing of how the value is kept.
    static let borrows: Set<String> = ["utf8", "utf16", "unicodeScalars"]

    /// Whether a place is reached through a projected value: it is a `$`
    /// name, as `$on` is, or its path of members starts at one, as
    /// `$model.settings.name` does.
    private static func isProjected(_ place: Syntax) -> Bool {
        if place.as(DeclReferenceExprSyntax.self)?.baseName.text.hasPrefix("$") == true { return true }
        var at = place.as(MemberAccessExprSyntax.self)?.base
        while let member = at?.as(MemberAccessExprSyntax.self) { at = member.base }
        return at?.as(DeclReferenceExprSyntax.self)?.baseName.text.hasPrefix("$") == true
    }

    /// Whether `operator` assigns to what stands before it: `=`, `+=`, ...
    private static func assigns(_ element: ExprSyntax) -> Bool {
        if element.is(AssignmentExprSyntax.self) { return true }
        guard let binary = element.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        let comparisons: Set<String> = ["==", "!=", "<=", ">=", "===", "!=="]
        return text.hasSuffix("=") && !comparisons.contains(text)
    }

    /// The declaration whose name is at `position`.
    func declaration(at position: SourcePosition) -> Declaration? {
        declarations[position]
    }

    /// The body of the function, subscript or computed property named at `position`.
    func body(at position: SourcePosition) -> FunctionBody? {
        guard let declaration = declarations[position] else { return nil }
        return FunctionBody(declaration: declaration, position: self.position)
    }
}
