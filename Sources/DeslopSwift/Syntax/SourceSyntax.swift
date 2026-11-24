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
    /// `isField` tells whether a member named at a position is a stored
    /// field, through which the place goes on: `queue.inner.items.count`
    /// reaches into `inner` as it does into `items`.
    func access(at position: SourcePosition, isField: (SourcePosition) -> Bool) -> Access {
        guard tokens[position] != nil else { return .reach }
        // A name that is no expression, such as an argument label of a
        // memberwise initializer, gives or takes the value whole.
        guard let place = place(at: position) else { return .copy }
        return access(of: place, isField: isField)
    }

    /// What the code does with what the method it calls at `position` hands
    /// out, as `access(at:isField:)` reads a field: `queue.head().count`
    /// reaches into what `head()` lends. A method not called where it is
    /// named, but passed on, reaches.
    func callAccess(at position: SourcePosition, isField: (SourcePosition) -> Bool) -> Access {
        guard let place = place(at: position),
              let call = place.parent?.as(FunctionCallExprSyntax.self),
              call.calledExpression.id == place.id else { return .reach }
        return access(of: Syntax(call), isField: isField)
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

    private func access(of place: Syntax, isField: (SourcePosition) -> Bool) -> Access {
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
                if isField(position(member.declName.baseName)) {
                    current = parent
                    continue
                }
                return SourceSyntax.borrows.contains(member.declName.baseName.text) ? .borrow : .call
            }
            if let subscripted = parent.as(SubscriptCallExprSyntax.self), subscripted.calledExpression.id == current.id {
                return .reach
            }
            if let call = parent.as(FunctionCallExprSyntax.self), call.calledExpression.id == current.id {
                return .call
            }
            if parent.is(InOutExprSyntax.self) {
                return .reach
            }
            if parent.is(KeyPathPropertyComponentSyntax.self) {
                return SourceSyntax.keyPathAccess(Syntax(parent))
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

    /// What a key path does with the field its component names: writes it
    /// when it is declared writable, `let path: WritableKeyPath<Queue, [Int]>
    /// = \.items`; reads it otherwise, as `queues.map(\.label)` does.
    private static func keyPathAccess(_ component: Syntax) -> Access {
        var at: Syntax? = component
        while let node = at, !node.is(KeyPathExprSyntax.self) { at = node.parent }
        guard let binding = at?.parent?.as(InitializerClauseSyntax.self)?.parent?.as(PatternBindingSyntax.self),
              let written = binding.typeAnnotation?.type else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): only a key path declared writable
            // where it is bound is known to write. One whose writability is
            // inferred, passed as an argument, or returned (`let p = \Queue.items`
            // then `q[keyPath: p].removeAll()`) is taken for a read, so a write
            // through it is missed. Every key path component that names a field
            // takes this path. Done when a key path's use is followed to where it
            // writes, with tests for inferred, passed and read-only key paths.
            return .copy
        }
        let name = written.as(IdentifierTypeSyntax.self)?.name.text
        return name == "WritableKeyPath" || name == "ReferenceWritableKeyPath" ? .reach : .copy
    }

    /// Members that lend a view of a value to read it, as Rust's `as_bytes`
    /// borrows: they hand out nothing of how the value is kept.
    static let borrows: Set<String> = ["utf8", "utf16", "unicodeScalars"]

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
