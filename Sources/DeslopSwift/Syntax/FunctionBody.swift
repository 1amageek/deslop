import SwiftSyntax

/// What a function's, subscript's or computed property's body does, as far
/// as wrappers are told by it.
struct FunctionBody {
    let parameters: [String]
    let signature: [String]
    /// The call that is all the body does, if that is all.
    let onlyCall: CallShape?
    /// The body does more than hand out or overwrite names: it calls, runs
    /// an operator, reaches a member of something other than `self`, or
    /// decides something.
    let computes: Bool
    /// The body assigns, or the declaration has a setter.
    let writes: Bool

    init(declaration: Declaration, position: (TokenSyntax) -> SourcePosition) {
        parameters = declaration.parameters
        signature = declaration.signature
        let detector = ComputeDetector()
        for body in declaration.bodies {
            detector.walk(body)
        }
        computes = detector.computes
        writes = detector.assigns || declaration.hasSetter
        if declaration.bodies.count == 1, !declaration.hasSetter {
            onlyCall = FunctionBody.onlyCall(declaration.bodies[0], parameters: declaration.parameters, position: position)
        } else {
            onlyCall = nil
        }
    }

    private static func onlyCall(
        _ statements: CodeBlockItemListSyntax,
        parameters: [String],
        position: (TokenSyntax) -> SourcePosition
    ) -> CallShape? {
        guard statements.count == 1, let item = statements.first else { return nil }
        var expression: ExprSyntax
        switch item.item {
        case .expr(let value):
            expression = value
        case .stmt(let statement):
            guard let returned = statement.as(ReturnStmtSyntax.self)?.expression else { return nil }
            expression = returned
        default:
            return nil
        }
        while true {
            if let tried = expression.as(TryExprSyntax.self) {
                expression = tried.expression
            } else if let awaited = expression.as(AwaitExprSyntax.self) {
                expression = awaited.expression
            } else {
                break
            }
        }
        let callee: ExprSyntax
        let arguments: [String?]
        let isCall: Bool
        if let call = expression.as(FunctionCallExprSyntax.self) {
            guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else { return nil }
            callee = call.calledExpression
            arguments = call.arguments.map { argument in
                guard let name = argument.expression.as(DeclReferenceExprSyntax.self),
                      name.argumentNames == nil else { return nil }
                return name.baseName.text
            }
            isCall = true
        } else {
            callee = expression
            arguments = []
            isCall = false
        }
        if let name = callee.as(DeclReferenceExprSyntax.self) {
            return CallShape(base: .unwritten, path: [], callee: position(name.baseName), arguments: arguments, isCall: isCall)
        }
        guard let member = callee.as(MemberAccessExprSyntax.self), var receiver = member.base else { return nil }
        var path: [SourcePosition] = []
        while let step = receiver.as(MemberAccessExprSyntax.self), let base = step.base {
            path.insert(position(step.declName.baseName), at: 0)
            receiver = base
        }
        guard let root = receiver.as(DeclReferenceExprSyntax.self) else { return nil }
        let base: CallShape.Base
        if root.baseName.tokenKind == .keyword(.self) {
            base = .selfValue
        } else if parameters.contains(root.baseName.text) {
            base = .parameter(root.baseName.text)
        } else {
            base = .implicitSelf
            path.insert(position(root.baseName), at: 0)
        }
        return CallShape(
            base: base, path: path, callee: position(member.declName.baseName), arguments: arguments, isCall: isCall
        )
    }
}

/// Finds whether a body does anything but name things, hand them out, and
/// assign them.
private final class ComputeDetector: SyntaxAnyVisitor {
    private(set) var computes = false
    private(set) var assigns = false

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        switch node.kind {
        case .codeBlockItemList, .codeBlockItem, .returnStmt, .expressionStmt, .sequenceExpr, .exprList,
             .declReferenceExpr, .tupleExpr, .labeledExprList, .labeledExpr, .token,
             .integerLiteralExpr, .floatLiteralExpr, .booleanLiteralExpr, .nilLiteralExpr,
             .stringLiteralExpr, .stringLiteralSegmentList, .stringSegment:
            return .visitChildren
        case .assignmentExpr:
            assigns = true
            return .visitChildren
        case .memberAccessExpr:
            let base = node.as(MemberAccessExprSyntax.self)?.base?.as(DeclReferenceExprSyntax.self)
            if base?.baseName.tokenKind != .keyword(.self) { computes = true }
            return .visitChildren
        case .binaryOperatorExpr:
            let text = node.as(BinaryOperatorExprSyntax.self)?.operator.text ?? ""
            if text.hasSuffix("="), !["==", "!=", "<=", ">=", "===", "!=="].contains(text) {
                assigns = true
            }
            computes = true
            return .visitChildren
        default:
            computes = true
            return .visitChildren
        }
    }
}
