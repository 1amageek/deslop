import SwiftSyntax

/// Follows a key path from where it is written to where its value goes, to
/// tell what is done with the field it names. A key path itself only names a
/// field; what writes the field is code that applies a writable one.
///
/// Where the value goes, and what that does:
/// - applied in a `[keyPath:]` subscript: what is done there with the field;
/// - passed to a function, subscript, initializer, attribute, macro or
///   operator: a write when the signature of what it is passed to declares a
///   writable key path, as the index's USR of it says, and a read when it
///   declares none;
/// - bound or assigned to a local: what each use of the local that may see
///   it does, at most; iterated by `for`: what each use of the loop's name does;
/// - stored in, assigned to, or returned from a property, function or
///   subscript the index names: what the code that uses it does, as
///   `NameFacts.keyPathFlow` follows it across files; returned from a local
///   function or closure: what is done with what it returns;
/// - put in an array, dictionary or tuple, in parentheses, in a branch of a
///   conditional or of an `if` or `switch` expression, on either side of `??`,
///   or cast to a writable key path: what is done with the whole;
/// - cast to any other type, compared, matched against, interpolated, or
///   discarded: a read; what holds it, assigned to: nothing is done with it.
///
/// A value that goes anywhere else may be written through, and is taken for a write.
struct KeyPathFlow {
    let syntax: SourceSyntax
    let facts: NameFacts
    /// How many steps a value is followed through before it is taken for a
    /// write: a bound on the work, which syntax alone never reaches, since
    /// each step goes up the tree or on to a later use.
    private static let mostSteps = 256

    /// What the key path whose component is `component` does with the field
    /// the component names.
    func access(ofComponent component: Syntax) -> Access {
        var at: Syntax? = component
        while let node = at, !node.is(KeyPathExprSyntax.self) { at = node.parent }
        guard let keyPath = at else { return .reach }
        return use(of: keyPath)
    }

    /// What is done with the key path, or with what holds it, at `value`.
    func use(of value: Syntax) -> Access {
        use(of: value, steps: 0)
    }

    private func use(of value: Syntax, steps: Int) -> Access {
        guard steps < KeyPathFlow.mostSteps, let parent = value.parent else { return .reach }
        let next = { (node: Syntax) in self.use(of: node, steps: steps + 1) }
        if let element = parent.as(LabeledExprSyntax.self), let list = element.parent?.as(LabeledExprListSyntax.self) {
            return argument(element, in: list, steps: steps)
        }
        if parent.is(ArrayElementSyntax.self) || parent.is(DictionaryElementSyntax.self) {
            guard let collection = parent.parent?.parent else { return .reach }
            return next(collection)
        }
        if let initializer = parent.as(InitializerClauseSyntax.self), initializer.value.id == value.id,
           let binding = initializer.parent?.as(PatternBindingSyntax.self) {
            return bound(binding, steps: steps)
        }
        if parent.is(ReturnStmtSyntax.self) {
            return returned(from: parent, steps: steps)
        }
        if let item = parent.as(CodeBlockItemSyntax.self) {
            return statement(item, steps: steps)
        }
        if let ternary = parent.as(UnresolvedTernaryExprSyntax.self), ternary.thenExpression.id == value.id {
            guard let sequence = ternary.parent?.parent, sequence.is(SequenceExprSyntax.self),
                  ternary.parent?.as(ExprListSyntax.self)?.count == 3 else { return .reach }
            return next(sequence)
        }
        if let list = parent.as(ExprListSyntax.self), let sequence = parent.parent, sequence.is(SequenceExprSyntax.self) {
            return operand(value, of: Array(list), in: sequence, steps: steps)
        }
        if let call = parent.as(FunctionCallExprSyntax.self) {
            // A closure or local function called where it is written hands on
            // what it returns; one passed as a trailing closure goes to the
            // function called.
            if call.calledExpression.id == value.id { return next(Syntax(call)) }
            return callee(call)
        }
        if parent.is(MultipleTrailingClosureElementSyntax.self),
           let call = parent.parent?.parent?.as(FunctionCallExprSyntax.self) {
            return callee(call)
        }
        if let loop = parent.as(ForStmtSyntax.self), loop.sequence.id == value.id {
            guard let name = loop.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return .reach }
            return uses(of: name, after: loop.pattern.endPosition, in: Syntax(loop.body.statements), steps: steps)
        }
        if let outer = parent.as(IfExprSyntax.self), value.is(IfExprSyntax.self) {
            // `else if`: a branch of the outer `if`.
            return next(Syntax(outer))
        }
        if parent.is(ExpressionPatternSyntax.self) {
            return .copy
        }
        return .reach
    }

    /// What is done with a value passed as `element` of `list`.
    private func argument(_ element: LabeledExprSyntax, in list: LabeledExprListSyntax, steps: Int) -> Access {
        guard let holder = list.parent else { return .reach }
        if holder.is(TupleExprSyntax.self) {
            return use(of: holder, steps: steps + 1)
        }
        if let subscripted = holder.as(SubscriptCallExprSyntax.self) {
            if element.label?.text == "keyPath" {
                // The index marks no write at a key path's component, so a
                // member reached through `[keyPath:]` may mutate what it
                // names: it reaches.
                let reached = syntax.access(of: Syntax(subscripted), facts: facts)
                return reached == .call || reached == .subscripted ? .reach : reached
            }
            return signature(at: subscripted.leftSquare)
        }
        if let call = holder.as(FunctionCallExprSyntax.self) {
            return callee(call)
        }
        if let macro = holder.as(MacroExpansionExprSyntax.self) {
            return signature(at: macro.macroName)
        }
        if let attribute = holder.as(AttributeSyntax.self) {
            if let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name
                ?? attribute.attributeName.as(MemberTypeSyntax.self)?.name {
                return signature(at: name)
            }
            return .reach
        }
        if holder.is(ExpressionSegmentSyntax.self) {
            return .copy
        }
        return .reach
    }

    /// What the function `call` calls does with a value passed to it.
    private func callee(_ call: FunctionCallExprSyntax) -> Access {
        var called = call.calledExpression
        if let specialized = called.as(GenericSpecializationExprSyntax.self) { called = specialized.expression }
        if let name = called.as(DeclReferenceExprSyntax.self)?.baseName
            ?? called.as(MemberAccessExprSyntax.self)?.declName.baseName {
            return signature(at: name)
        }
        return .reach
    }

    /// What the declaration the index names at `token` does with a key path
    /// passed to it, as its signature declares.
    private func signature(at token: TokenSyntax) -> Access {
        switch facts.keyPathSignature(syntax.position(token)) {
        case .readOnly:
            return .copy
        case .writable, .unknown, nil:
            return .reach
        }
    }

    /// What is done with a value a pattern binding binds.
    private func bound(_ binding: PatternBindingSyntax, steps: Int) -> Access {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else { return .reach }
        if let flow = facts.keyPathFlow(syntax.position(name)) { return flow }
        guard let scope = KeyPathFlow.scope(of: Syntax(binding)) else { return .reach }
        return uses(of: name.text, after: binding.endPosition, in: scope, steps: steps)
    }

    /// What the uses of the local `name` in `scope` after `start` do, at most.
    private func uses(of name: String, after start: AbsolutePosition, in scope: Syntax, steps: Int) -> Access {
        let uses = scope.tokens(viewMode: .sourceAccurate).compactMap { token -> Syntax? in
            guard token.text == name, token.positionAfterSkippingLeadingTrivia > start,
                  let reference = token.parent, reference.is(DeclReferenceExprSyntax.self) else { return nil }
            // `other.name` names a member, not the local.
            if let member = reference.parent?.as(MemberAccessExprSyntax.self), member.declName.id == reference.id {
                return nil
            }
            return reference
        }
        return uses.map { use(of: $0, steps: steps + 1) }.max() ?? .copy
    }

    /// What is done with what the declaration around `node` returns.
    private func returned(from node: Syntax, steps: Int) -> Access {
        var at = node.parent
        while let current = at {
            if let closure = current.as(ClosureExprSyntax.self) {
                if let written = closure.signature?.returnClause?.type, !KeyPathFlow.isWritable(Syntax(written)) {
                    return .copy
                }
                return use(of: current, steps: steps + 1)
            }
            if let function = current.as(FunctionDeclSyntax.self) {
                return declared(function.name, in: current, steps: steps)
            }
            if let subscriptDecl = current.as(SubscriptDeclSyntax.self) {
                return facts.keyPathFlow(syntax.position(subscriptDecl.subscriptKeyword)) ?? .reach
            }
            if let binding = current.as(PatternBindingSyntax.self) {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else { return .reach }
                return declared(name, in: current, steps: steps)
            }
            if current.is(InitializerDeclSyntax.self) || current.is(DeinitializerDeclSyntax.self) {
                return .copy
            }
            at = current.parent
        }
        return .reach
    }

    /// What is done with what the function or computed property whose name
    /// is `name` returns: as the index follows it, or, for a local one, what
    /// its uses in the code around it do.
    private func declared(_ name: TokenSyntax, in declaration: Syntax, steps: Int) -> Access {
        if let flow = facts.keyPathFlow(syntax.position(name)) { return flow }
        guard let scope = KeyPathFlow.scope(of: declaration) else { return .reach }
        return uses(of: name.text, after: declaration.endPosition, in: scope, steps: steps)
    }

    /// What is done with a value that is a statement of its own: the value
    /// of a body it is all of, or nothing.
    private func statement(_ item: CodeBlockItemSyntax, steps: Int) -> Access {
        guard let list = item.parent?.as(CodeBlockItemListSyntax.self), list.count == 1, let body = list.parent else {
            return .copy
        }
        if body.is(ClosureExprSyntax.self) || body.is(AccessorBlockSyntax.self) {
            return returned(from: Syntax(list), steps: steps)
        }
        if let block = body.as(CodeBlockSyntax.self), let owner = block.parent {
            if owner.is(FunctionDeclSyntax.self) || owner.is(AccessorDeclSyntax.self) {
                return returned(from: Syntax(block), steps: steps)
            }
            if owner.is(IfExprSyntax.self) {
                return use(of: owner, steps: steps + 1)
            }
            return .copy
        }
        if body.is(SwitchCaseSyntax.self), let switchExpression = body.parent?.parent, switchExpression.is(SwitchExprSyntax.self) {
            return use(of: switchExpression, steps: steps + 1)
        }
        return .copy
    }

    /// What is done with `value`, an operand of the unfolded sequence `elements`.
    private func operand(_ value: Syntax, of elements: [ExprSyntax], in sequence: Syntax, steps: Int) -> Access {
        guard let at = elements.firstIndex(where: { $0.id == value.id }) else { return .reach }
        if elements.count == 3 {
            let operation = elements[1]
            if operation.is(UnresolvedAsExprSyntax.self), at == 0 {
                return KeyPathFlow.isWritable(Syntax(elements[2])) ? use(of: sequence, steps: steps + 1) : .copy
            }
            if operation.is(UnresolvedTernaryExprSyntax.self) {
                return at == 2 ? use(of: sequence, steps: steps + 1) : .copy
            }
            if let binary = operation.as(BinaryOperatorExprSyntax.self), binary.operator.text == "??" {
                return use(of: sequence, steps: steps + 1)
            }
            if operation.is(AssignmentExprSyntax.self) {
                // What is assigned to hands nothing on: its value is replaced.
                return at == 2 ? assigned(to: elements[0], in: sequence, steps: steps) : .copy
            }
        }
        // Compared or combined by operators that each take no writable key
        // path: `path == \.items`, `a == \.x || b == \.y`.
        let neighbours = [at - 1, at + 1].filter(elements.indices.contains).map { elements[$0] }
        let readOnly = neighbours.allSatisfy { neighbour in
            guard let binary = neighbour.as(BinaryOperatorExprSyntax.self), binary.operator.text != "??" else { return false }
            return facts.keyPathSignature(syntax.position(binary.operator)) == .readOnly
        }
        return readOnly ? .copy : .reach
    }

    /// What is done with a value assigned to `target`.
    /// What is assigned to a property is what the code that uses the
    /// property does with it; what is assigned to a local, what the uses of
    /// the local that may see it do: those after the assignment in the code
    /// that declares the local, or, in a loop, any in the loop.
    private func assigned(to target: ExprSyntax, in sequence: Syntax, steps: Int) -> Access {
        if target.is(DiscardAssignmentExprSyntax.self) { return .copy }
        if let tuple = target.as(TupleExprSyntax.self) {
            // `(a, b) = (b, a)`: what is assigned may go to any of them.
            return tuple.elements.map { assigned(to: $0.expression, in: sequence, steps: steps + 1) }.max() ?? .copy
        }
        if let member = target.as(MemberAccessExprSyntax.self) {
            return facts.keyPathFlow(syntax.position(member.declName.baseName)) ?? .reach
        }
        guard let name = target.as(DeclReferenceExprSyntax.self)?.baseName else { return .reach }
        if let flow = facts.keyPathFlow(syntax.position(name)) { return flow }
        var start = sequence.endPosition
        var at = sequence.parent
        while let current = at {
            if let list = current.as(CodeBlockItemListSyntax.self), KeyPathFlow.declares(list, name.text) {
                return uses(of: name.text, after: start, in: current, steps: steps)
            }
            if current.is(ForStmtSyntax.self) || current.is(WhileStmtSyntax.self) || current.is(RepeatStmtSyntax.self) {
                start = current.position
            }
            at = current.parent
        }
        // A parameter, or a local of code around a closure: not followed.
        return .reach
    }

    /// Whether the statements of `list` declare a local named `name`.
    private static func declares(_ list: CodeBlockItemListSyntax, _ name: String) -> Bool {
        list.contains { item in
            item.item.as(VariableDeclSyntax.self)?.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
            } == true
        }
    }

    /// Whether a written type names a writable key path.
    private static func isWritable(_ type: Syntax) -> Bool {
        type.tokens(viewMode: .sourceAccurate).contains { token in
            token.text == "WritableKeyPath" || token.text == "ReferenceWritableKeyPath"
        }
    }

    /// The code a declaration is written in: the innermost list of
    /// statements around it.
    private static func scope(of node: Syntax) -> Syntax? {
        var at = node.parent
        while let current = at, !current.is(CodeBlockItemListSyntax.self) { at = current.parent }
        return at
    }
}
