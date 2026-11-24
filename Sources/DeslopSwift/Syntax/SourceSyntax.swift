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

    /// The names of the declarations around `position`, innermost first.
    func holders(of position: SourcePosition) -> [SourcePosition] {
        guard let token = tokens[position] else { return [] }
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
        guard tokens[position] != nil else { return .reach }
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
        guard let token = tokens[position], let reference = token.parent?.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        if let member = reference.parent?.as(MemberAccessExprSyntax.self), member.declName.id == reference.id {
            return Syntax(member)
        }
        return Syntax(reference)
    }

    private func access(of place: Syntax, facts: NameFacts) -> Access {
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
                return keyPathAccess(Syntax(parent), facts: facts)
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

    /// What a key path does with the field its component names: what is
    /// done where the key path is used. A key path used in a subscript,
    /// `q[keyPath: \.items]`, is the field there; one bound to a name is used
    /// wherever the name is, in the code that binds it; one passed to a
    /// function is written when the function takes a writable key path; one
    /// declared writable where it is bound writes. Of several uses, the most
    /// it does counts.
    private func keyPathAccess(_ component: Syntax, facts: NameFacts) -> Access {
        var at: Syntax? = component
        while let node = at, !node.is(KeyPathExprSyntax.self) { at = node.parent }
        guard let keyPath = at else { return .copy }
        if let binding = keyPath.parent?.as(InitializerClauseSyntax.self)?.parent?.as(PatternBindingSyntax.self) {
            if let written = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self)?.name.text,
               written == "WritableKeyPath" || written == "ReferenceWritableKeyPath" {
                return .reach
            }
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let scope = SourceSyntax.scope(of: Syntax(binding)) else {
                return .copy
            }
            let uses = scope.tokens(viewMode: .sourceAccurate).filter { token in
                token.text == name && token.positionAfterSkippingLeadingTrivia > binding.endPosition
                    && token.parent?.is(DeclReferenceExprSyntax.self) == true
            }
            return uses.compactMap { $0.parent }.map { use(of: $0, facts: facts) }.max() ?? .copy
        }
        return use(of: keyPath, facts: facts)
    }

    /// What is done with a key path, written at `value`, where it is used.
    private func use(of value: Syntax, facts: NameFacts) -> Access {
        guard let argument = value.parent?.as(LabeledExprSyntax.self),
              let list = argument.parent?.as(LabeledExprListSyntax.self) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): a key path that is neither used
            // in a subscript, nor passed to a function, nor bound to a name used
            // so in the code that binds it (one stored in a property, returned,
            // or put in a collection) is taken for a read of its field, so a
            // write through it elsewhere is missed. Every such key path takes
            // this path. Done when a key path is followed through properties
            // and returns, with tests for each.
            return .copy
        }
        if let subscripted = list.parent?.as(SubscriptCallExprSyntax.self), argument.label?.text == "keyPath" {
            // The index marks no write at a key path's component, so a member
            // reached through `[keyPath:]` may mutate what it names: it reaches.
            let reached = access(of: Syntax(subscripted), facts: facts)
            return reached == .call || reached == .subscripted ? .reach : reached
        }
        if let call = list.parent?.as(FunctionCallExprSyntax.self), let callee = SourceSyntax.calleeName(call) {
            return facts.takesWritableKeyPath(position(callee)) ? .reach : .copy
        }
        return .copy
    }

    /// The name a call names: `write` for `write(&q, \.items)` and `q.write(\.items)`.
    private static func calleeName(_ call: FunctionCallExprSyntax) -> TokenSyntax? {
        if let name = call.calledExpression.as(DeclReferenceExprSyntax.self) { return name.baseName }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) { return member.declName.baseName }
        return nil
    }

    /// The code a declaration is written in: the innermost list of
    /// statements around it.
    private static func scope(of node: Syntax) -> Syntax? {
        var at = node.parent
        while let current = at, !current.is(CodeBlockItemListSyntax.self) { at = current.parent }
        return at
    }

    /// Members that lend a view of a value to read it, as Rust's `as_bytes`
    /// borrows: they hand out nothing of how the value is kept.
    static let borrows: Set<String> = ["utf8", "utf16", "unicodeScalars"]

    /// Whether a place is reached through a projected value: its path of
    /// members starts at a `$` name, as `$model.settings.name` does.
    private static func isProjected(_ place: Syntax) -> Bool {
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
