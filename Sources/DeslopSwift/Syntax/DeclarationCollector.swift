import SwiftSyntax

/// Finds every declaration of a file that the index can name, by the
/// position of its name.
final class DeclarationCollector: SyntaxVisitor {
    private let position: (TokenSyntax) -> SourcePosition
    private var declarations: [SourcePosition: Declaration] = [:]

    private init(position: @escaping (TokenSyntax) -> SourcePosition) {
        self.position = position
        super.init(viewMode: .sourceAccurate)
    }

    /// Every declaration of `tree` the index can name, by the position of
    /// its name as `position` gives it.
    static func declarations(
        in tree: SourceFileSyntax,
        position: @escaping (TokenSyntax) -> SourcePosition
    ) -> [SourcePosition: Declaration] {
        let collector = DeclarationCollector(position: position)
        collector.walk(tree)
        return collector.declarations
    }

    private func range(_ node: some SyntaxProtocol) -> Range<Int> {
        node.positionAfterSkippingLeadingTrivia.utf8Offset..<node.endPositionBeforeTrailingTrivia.utf8Offset
    }

    private func add(_ name: TokenSyntax, _ declaration: Declaration) {
        declarations[position(name)] = declaration
    }

    private func typeDeclaration(_ node: some SyntaxProtocol) -> Declaration {
        Declaration(
            kind: .type, isStatic: false, declaredType: nil, parameters: [], signature: [],
            bodies: [], hasSetter: false, range: range(node)
        )
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, typeDeclaration(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, typeDeclaration(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, typeDeclaration(node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, typeDeclaration(node))
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, typeDeclaration(node))
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, typeDeclaration(node))
        return .visitChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, typeDeclaration(node))
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let signature = node.signature
        add(node.name, Declaration(
            kind: .function,
            isStatic: DeclarationCollector.isStatic(node.modifiers),
            declaredType: nil,
            parameters: DeclarationCollector.parameterNames(signature.parameterClause.parameters),
            signature: DeclarationCollector.tokens(signature.parameterClause.parameters)
                + (signature.returnClause.map { DeclarationCollector.tokens($0.type) } ?? []),
            bodies: node.body.map { [$0.statements] } ?? [],
            hasSetter: false,
            range: range(node)
        ))
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let parameters = node.signature.parameterClause.parameters
        add(node.initKeyword, Declaration(
            kind: .initializer,
            isStatic: false,
            declaredType: nil,
            parameters: DeclarationCollector.parameterNames(parameters),
            signature: DeclarationCollector.tokens(parameters),
            bodies: node.body.map { [$0.statements] } ?? [],
            hasSetter: false,
            range: range(node)
        ))
        return .visitChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.deinitKeyword, Declaration(
            kind: .deinitializer, isStatic: false, declaredType: nil, parameters: [], signature: [],
            bodies: node.body.map { [$0.statements] } ?? [], hasSetter: false, range: range(node)
        ))
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        let parameters = node.parameterClause.parameters
        let accessors = DeclarationCollector.accessors(node.accessorBlock)
        add(node.subscriptKeyword, Declaration(
            kind: .subscript,
            isStatic: DeclarationCollector.isStatic(node.modifiers),
            declaredType: DeclarationCollector.tokens(node.returnClause.type),
            parameters: DeclarationCollector.parameterNames(parameters),
            signature: DeclarationCollector.tokens(parameters) + DeclarationCollector.tokens(node.returnClause.type),
            bodies: accessors.bodies,
            hasSetter: accessors.hasSetter,
            range: range(node)
        ))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = DeclarationCollector.isStatic(node.modifiers)
        for binding in node.bindings {
            let annotated = binding.typeAnnotation.map { DeclarationCollector.tokens($0.type) }
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let accessors = DeclarationCollector.accessors(binding.accessorBlock)
                var declaration = Declaration(
                    kind: accessors.computed ? .computedProperty : .storedProperty,
                    isStatic: isStatic,
                    declaredType: annotated ?? binding.initializer.flatMap { DeclarationCollector.literalType($0.value) },
                    parameters: [],
                    signature: annotated ?? [],
                    bodies: accessors.bodies,
                    hasSetter: accessors.hasSetter,
                    range: range(binding)
                )
                if annotated == nil, let value = binding.initializer?.value {
                    declaration.constructed = constructed(value)
                }
                add(pattern.identifier, declaration)
            } else if let tuple = binding.pattern.as(TuplePatternSyntax.self) {
                addTuple(
                    tuple,
                    type: binding.typeAnnotation?.type.as(TupleTypeSyntax.self),
                    value: binding.initializer?.value.as(TupleExprSyntax.self),
                    isStatic: isStatic,
                    range: range(binding)
                )
            }
        }
        return .visitChildren
    }

    /// Each name of a tuple pattern, `var (left, right): ([Int], [Int])`, as
    /// a stored property of the type the tuple's type or value gives it.
    private func addTuple(
        _ tuple: TuplePatternSyntax,
        type: TupleTypeSyntax?,
        value: TupleExprSyntax?,
        isStatic: Bool,
        range: Range<Int>
    ) {
        let types = type.map { Array($0.elements) }
        let values = value.map { Array($0.elements) }
        for (index, element) in tuple.elements.enumerated() {
            let elementType = types.flatMap { index < $0.count ? DeclarationCollector.tokens($0[index].type) : nil }
            let elementValue = values.flatMap { index < $0.count ? $0[index].expression : nil }
            if let name = element.pattern.as(IdentifierPatternSyntax.self) {
                var declaration = Declaration(
                    kind: .storedProperty,
                    isStatic: isStatic,
                    declaredType: elementType ?? elementValue.flatMap(DeclarationCollector.literalType),
                    parameters: [],
                    signature: elementType ?? [],
                    bodies: [],
                    hasSetter: false,
                    range: range
                )
                if elementType == nil, let elementValue {
                    declaration.constructed = constructed(elementValue)
                }
                add(name.identifier, declaration)
            } else if let nested = element.pattern.as(TuplePatternSyntax.self) {
                let nestedType = types.flatMap { index < $0.count ? $0[index].type.as(TupleTypeSyntax.self) : nil }
                addTuple(nested, type: nestedType, value: elementValue?.as(TupleExprSyntax.self), isStatic: isStatic, range: range)
            }
        }
    }

    /// The type `value` constructs, if it is a call of a type's name:
    /// `Inner()`, `Outer.Inner(size: 2)`, `Box<Int>()`, `[Int]()`.
    private func constructed(_ value: ExprSyntax) -> Declaration.Constructed? {
        guard let call = value.as(FunctionCallExprSyntax.self) else { return nil }
        let callee = call.calledExpression
        if callee.is(ArrayExprSyntax.self) || callee.is(DictionaryExprSyntax.self) {
            return Declaration.Constructed(tokens: DeclarationCollector.tokens(callee), position: nil)
        }
        var named = callee
        if let generic = named.as(GenericSpecializationExprSyntax.self) {
            named = generic.expression
        }
        let name: TokenSyntax
        if let reference = named.as(DeclReferenceExprSyntax.self) {
            name = reference.baseName
        } else if let member = named.as(MemberAccessExprSyntax.self), member.base != nil {
            name = member.declName.baseName
        } else {
            return nil
        }
        return Declaration.Constructed(tokens: DeclarationCollector.tokens(callee), position: position(name))
    }

    override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
        add(node.name, Declaration(
            kind: .enumCase, isStatic: false, declaredType: nil, parameters: [], signature: [],
            bodies: [], hasSetter: false, range: range(node)
        ))
        return .visitChildren
    }

    /// What a property's or subscript's accessor block says: whether it
    /// computes a value rather than storing one, the bodies of its accessors,
    /// and whether one of them sets. Observers (`willSet`, `didSet`) and
    /// `init` accessors leave a property stored.
    private static func accessors(_ block: AccessorBlockSyntax?) -> (computed: Bool, bodies: [CodeBlockItemListSyntax], hasSetter: Bool) {
        guard let block else { return (false, [], false) }
        switch block.accessors {
        case .getter(let statements):
            return (true, [statements], false)
        case .accessors(let list):
            let observing: Set<String> = ["willSet", "didSet", "init"]
            let kinds = list.map(\.accessorSpecifier.text)
            let computed = kinds.contains { !observing.contains($0) }
            let bodies = computed ? list.compactMap { $0.body?.statements } : []
            let setter = kinds.contains("set") || kinds.contains("_modify") || kinds.contains("modify")
            return (computed, bodies, setter)
        }
    }

    private static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    private static func parameterNames(_ parameters: FunctionParameterListSyntax) -> [String] {
        parameters.map { ($0.secondName ?? $0.firstName).text }
    }

    static func tokens(_ node: some SyntaxProtocol) -> [String] {
        node.tokens(viewMode: .sourceAccurate).map(\.text)
    }

    /// The tokens of the parameters' types, in order.
    private static func tokens(_ parameters: FunctionParameterListSyntax) -> [String] {
        parameters.flatMap { tokens($0.type) }
    }

    /// The type a literal initial value gives a property whose type is not
    /// written: `0` and `-1` an `Int`, `0.5` a `Double`.
    private static func literalType(_ value: ExprSyntax) -> [String]? {
        if let negated = value.as(PrefixOperatorExprSyntax.self), negated.operator.text == "-",
           negated.expression.is(IntegerLiteralExprSyntax.self) || negated.expression.is(FloatLiteralExprSyntax.self) {
            return literalType(negated.expression)
        }
        if value.is(IntegerLiteralExprSyntax.self) { return ["Int"] }
        if value.is(FloatLiteralExprSyntax.self) { return ["Double"] }
        if value.is(BooleanLiteralExprSyntax.self) { return ["Bool"] }
        if value.is(StringLiteralExprSyntax.self) { return ["String"] }
        return nil
    }
}
