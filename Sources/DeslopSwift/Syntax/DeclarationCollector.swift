import SwiftSyntax

/// Finds every declaration of a file that the index can name, by the
/// position of its name.
final class DeclarationCollector: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private var declarations: [SourcePosition: Declaration] = [:]

    private init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Every declaration of `tree` the index can name, by the position of its name.
    static func declarations(in tree: SourceFileSyntax, converter: SourceLocationConverter) -> [SourcePosition: Declaration] {
        let collector = DeclarationCollector(converter: converter)
        collector.walk(tree)
        return collector.declarations
    }

    private func position(_ token: TokenSyntax) -> SourcePosition {
        let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
        return SourcePosition(line: location.line, column: location.column)
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
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let annotated = binding.typeAnnotation.map { DeclarationCollector.tokens($0.type) }
            let declaredType = annotated ?? binding.initializer.flatMap { DeclarationCollector.literalType($0.value) }
            let accessors = DeclarationCollector.accessors(binding.accessorBlock)
            add(pattern.identifier, Declaration(
                kind: accessors.computed ? .computedProperty : .storedProperty,
                isStatic: isStatic,
                declaredType: declaredType,
                parameters: [],
                signature: annotated ?? [],
                bodies: accessors.bodies,
                hasSetter: accessors.hasSetter,
                range: range(binding)
            ))
        }
        return .visitChildren
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

    /// The type a literal initial value gives a property whose type is not written.
    private static func literalType(_ value: ExprSyntax) -> [String]? {
        if value.is(IntegerLiteralExprSyntax.self) { return ["Int"] }
        if value.is(FloatLiteralExprSyntax.self) { return ["Double"] }
        if value.is(BooleanLiteralExprSyntax.self) { return ["Bool"] }
        if value.is(StringLiteralExprSyntax.self) { return ["String"] }
        return nil
    }
}
