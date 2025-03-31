//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// swift-format-ignore-file

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// db driver specifics
private let domain = "OracleNIO"
private let protocolName = "OraclePreparedStatement"
private let row = "OracleRow"
private let bindings = "OracleBindings"
private let bindPrefix = ":"

private enum StatementMacroDiagnosticMessages: DiagnosticMessage {
    case invalidDeclaration

    var diagnosticID: MessageID {
        switch self {
        case .invalidDeclaration:
            MessageID(domain: domain, id: "statement-invalid-declaration")
        }
    }

    var message: String {
        switch self {
        case .invalidDeclaration:
            "'@Statement' can only be applied to struct types"
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .invalidDeclaration:
                .error
        }
    }
}
private struct InvalidDeclarationFixIt: FixItMessage {
    var introducer: TokenSyntax
    var message: String { "Replace '\(introducer.text)' with 'struct'" }
    let fixItID = MessageID(domain: domain, id: "statement-invalid-declaration-fix-it")
}
private enum StatementMacroError: Error, DiagnosticMessage {
    case unprocessableInterpolation(name: String, isBind: Bool)

    var diagnosticID: MessageID {
        switch self {
        case .unprocessableInterpolation:
            MessageID(domain: domain, id: "unprocessable-interpolation")
        }
    }

    var message: String {
        switch self {
        case .unprocessableInterpolation(let name, let isBind):
            "Cannot parse type for \(isBind ? "bind" : "column") with name '\(name)'"
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .unprocessableInterpolation:
                .error
        }
    }
}

public struct OracleStatementMacro: ExtensionMacro, MemberMacro {
    private typealias Column = (name: String, type: TokenSyntax, isOptional: Bool, alias: String?)
    private typealias Bind = (name: String, type: TokenSyntax, isOptional: Bool)

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            return []
        }
        #if canImport(SwiftSyntax600)
        let protocols = protocols.map { InheritedTypeSyntax(type: $0) }
        #else
        let protocols = if protocols.isEmpty {
            // In tests, the protocol is not added before 600, so we'll add it manually
            [InheritedTypeSyntax(type: TypeSyntax(stringLiteral: protocolName))]
        } else {
            protocols.map { InheritedTypeSyntax(type: $0) }
        }
        #endif
        return [
            ExtensionDeclSyntax(
                extendedType: type,
                inheritanceClause: .init(inheritedTypes: InheritedTypeListSyntax(protocols)),
                memberBlockBuilder: {}
            )
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            #if canImport(SwiftSyntax600)
            context.diagnose(Diagnostic(
                node: node,
                message: StatementMacroDiagnosticMessages.invalidDeclaration,
                fixIt: FixIt(message: InvalidDeclarationFixIt(introducer: declaration.introducer), changes: [
                    FixIt.Change.replace(
                        oldNode: Syntax(declaration.introducer),
                        newNode: Syntax(TokenSyntax.keyword(.struct))
                    )
                ])
            ))
            #else
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: StatementMacroDiagnosticMessages.invalidDeclaration
                ))
            #endif
            return []
        }

        // It is fine to force unwrap here, because the compiler ensures we receive this exact syntax tree here.
        let unparsedString = node
            .arguments!.as(LabeledExprListSyntax.self)!
            .first!.expression.as(StringLiteralExprSyntax.self)!

        var sql: StringLiteralSegmentListSyntax = []
        var columns: [Column] = []
        var binds: [Bind] = []
        for element in unparsedString.segments {
            if let expression = element.as(ExpressionSegmentSyntax.self) {
                let interpolation = try extractInterpolations(expression)
                switch interpolation {
                case .column(let column):
                    columns.append(column)
                    sql.append(.init(StringSegmentSyntax(content: .stringSegment(column.name))))
                    if let alias = column.alias {
                        sql.append(.init(StringSegmentSyntax(content: .stringSegment(#" AS \"\#(alias)\""#))))
                    }
                case .bind(let bind):
                    binds.append(bind)
                    sql.append(.init(StringSegmentSyntax(content: .stringSegment("\(bindPrefix)\(binds.count)"))))
                }
            } else if let expression = element.as(StringSegmentSyntax.self) {
                sql.append(.init(expression))
            }
        }

        let rowDeclaration: DeclSyntax
        if columns.isEmpty {
            let rowAlias = TypeAliasDeclSyntax(name: .identifier("Row"), initializer: TypeInitializerClauseSyntax(value: IdentifierTypeSyntax(name: .identifier("Void"))))
            rowDeclaration = DeclSyntax(rowAlias)
        } else {
            let rowStruct = makeRowStruct(for: columns)
            rowDeclaration = DeclSyntax(rowStruct)
        }

        let staticSQL = VariableDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.static))],
            bindingSpecifier: .keyword(.let)
        ) {
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("sql")),
                initializer: InitializerClauseSyntax(
                    value: StringLiteralExprSyntax(
                        openingQuote: unparsedString.openingQuote,
                        segments: sql,
                        closingQuote: unparsedString.closingQuote
                    )
                )
            )
        }

        let bindings = binds.map { name, type, isOptional in
            VariableDeclSyntax(
                bindingSpecifier: .keyword(.var, leadingTrivia: .carriageReturnLineFeed, trailingTrivia: .space),
                bindings: PatternBindingListSyntax(
                    itemsBuilder: {
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                            typeAnnotation: makeTypeSyntax(type, optional: isOptional)
                        )
                    }
                )
            )
        }

        let makeBindings = binds.isEmpty ? makeEmptyBindings() : makeBindings(for: binds)
        let decodeRow = decodeRow(from: columns)

        return [
            rowDeclaration,
            DeclSyntax(staticSQL),
        ] + bindings.map(DeclSyntax.init) + [
            DeclSyntax(makeBindings),
            DeclSyntax(decodeRow)
        ]
    }

    private enum Interpolation {
        case column(Column)
        case bind(Bind)
    }
    private static func extractInterpolations(_ node: ExpressionSegmentSyntax) throws -> Interpolation {
        let tupleElements = node.expressions
        precondition(tupleElements.count >= 2, "Expected tuple with two or more elements, less are impossible as the compiler already checks for it")

        // First element needs to be the column name
        var iterator = tupleElements.makeIterator()
        let identifier = iterator.next()! as LabeledExprSyntax // works as tuple contains at least two elements
                                                               // Type can be force-unwrapped as the compiler ensures it is there.
        let rawType = iterator.next()!.expression.as(MemberAccessExprSyntax.self)!.base!
        #if canImport(SwiftSyntax600)
        let label = identifier.label?.identifier?.name
        #else
        let label = identifier.label?.text
        #endif
        let type: TokenSyntax
        let isOptional: Bool
        if let nonOptional = rawType.as(DeclReferenceExprSyntax.self)?.baseName {
            type = nonOptional
            isOptional = false
        } else if let optional = rawType.as(OptionalChainingExprSyntax.self)?.expression.as(
            DeclReferenceExprSyntax.self)?.baseName
        {
            type = optional
            isOptional = true
        } else {
            throw StatementMacroError.unprocessableInterpolation(
                name: identifier.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(
                    StringSegmentSyntax.self)?.content.text ?? "<invalid>",
                isBind: label == "bind"
            )
        }
        // Same thing as with type.
        let name = identifier.expression.as(StringLiteralExprSyntax.self)!
            .segments.first!.as(StringSegmentSyntax.self)!.content.text
        switch label {
        case "bind":
            return .bind((name: name, type: type, isOptional: isOptional))
        default:
            let alias = iterator.next()?.expression.as(StringLiteralExprSyntax.self)?
                .segments.first?.as(StringSegmentSyntax.self)?.content.text

            return .column((name: name, type: type, isOptional: isOptional, alias: alias))
        }
    }

    private static func makeRowStruct(for columns: [Column]) -> StructDeclSyntax {
        StructDeclSyntax(
            structKeyword: .keyword(.struct, trailingTrivia: .space),
            name: .identifier("Row", trailingTrivia: .space),
            memberBlockBuilder: {
                for (name, type, isOptional, alias) in columns {
                    MemberBlockItemSyntax(
                        decl: VariableDeclSyntax(
                            bindingSpecifier: .keyword(.var, trailingTrivia: .space),
                            bindings: PatternBindingListSyntax(
                                itemsBuilder: {
                                    PatternBindingSyntax(
                                        pattern: IdentifierPatternSyntax(identifier: .identifier(alias ?? name)),
                                        typeAnnotation: makeTypeSyntax(type, optional: isOptional)
                                    )
                                }
                            )
                        )
                    )
                }
            },
            trailingTrivia: Trivia.newline
        )
    }

    private static func makeBindings(for binds: [Bind]) -> FunctionDeclSyntax {
        FunctionDeclSyntax(
            name: .identifier("makeBindings"),
            signature: bindingsFunctionSignature(),
            body: CodeBlockSyntax(statementsBuilder: {
                CodeBlockItemSyntax(
                    item: .decl(DeclSyntax(
                        VariableDeclSyntax(
                            bindingSpecifier: .keyword(.var),
                            bindings: PatternBindingListSyntax(itemsBuilder: {
                                PatternBindingSyntax(
                                    pattern: IdentifierPatternSyntax(identifier: .identifier("bindings")),
                                    initializer: InitializerClauseSyntax(value: FunctionCallExprSyntax(
                                        calledExpression: DeclReferenceExprSyntax(baseName: .identifier(bindings)),
                                        leftParen: .leftParenToken(),
                                        arguments: [
                                            LabeledExprSyntax(
                                                label: "capacity",
                                                expression: IntegerLiteralExprSyntax(binds.count)
                                            )
                                        ],
                                        rightParen: .rightParenToken()
                                    ))
                                )
                            })
                        )
                    ))
                )
                for (bind, _, isOptional) in binds {
                    appendBind(bind, isOptional: isOptional)
                }
                CodeBlockItemSyntax(item: .stmt(StmtSyntax(ReturnStmtSyntax(
                    expression: DeclReferenceExprSyntax(baseName: .identifier("bindings"))
                ))))
            })
        )
    }

    private static func appendBind(_ name: String, isOptional: Bool) -> CodeBlockItemSyntax {
        if isOptional {
            CodeBlockItemSyntax(item: .expr(ExprSyntax(
                IfExprSyntax(
                    conditions: [
                        ConditionElementSyntax(condition: .optionalBinding(OptionalBindingConditionSyntax(
                            bindingSpecifier: .keyword(.let),
                            pattern: IdentifierPatternSyntax(identifier: .identifier(name))
                        )))
                    ],
                    body: CodeBlockSyntax(statements: [appendBind(name, isOptional: false)]),
                    elseKeyword: .keyword(.else),
                    elseBody: IfExprSyntax.ElseBody(
                        CodeBlockSyntax(
                            leftBrace: .leftBraceToken(),
                            statements: [CodeBlockItemSyntax(item: .expr(
                                ExprSyntax(FunctionCallExprSyntax(
                                    calledExpression: MemberAccessExprSyntax(
                                        base: DeclReferenceExprSyntax(baseName: .identifier("bindings")),
                                        declName: DeclReferenceExprSyntax(baseName: .identifier("appendNull"))
                                    ),
                                    leftParen: .leftParenToken(),
                                    arguments: [],
                                    rightParen: .rightParenToken()
                                ))
                            ))],
                            rightBrace: .rightBraceToken()
                        )
                    )
                )
            )))
        } else {
            CodeBlockItemSyntax(item: .expr(ExprSyntax(
                FunctionCallExprSyntax(
                    calledExpression: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: .identifier("bindings")),
                        declName: DeclReferenceExprSyntax(baseName: .identifier("append"))
                    ),
                    leftParen: .leftParenToken(),
                    arguments: [LabeledExprSyntax(label: nil, expression: DeclReferenceExprSyntax(baseName: .identifier(name)))],
                    rightParen: .rightParenToken()
                )
            )))
        }
    }

    private static func makeEmptyBindings() -> FunctionDeclSyntax {
        FunctionDeclSyntax(
            name: .identifier("makeBindings"),
            signature: bindingsFunctionSignature(),
            body: CodeBlockSyntax(statementsBuilder: {
                CodeBlockItemSyntax(
                    item: .stmt(StmtSyntax(
                        ReturnStmtSyntax(expression: FunctionCallExprSyntax(
                            calledExpression: DeclReferenceExprSyntax(baseName: .identifier(bindings)),
                            leftParen: .leftParenToken(),
                            arguments: [],
                            rightParen: .rightParenToken()
                        ))
                    ))
                )
            })
        )
    }

    private static func bindingsFunctionSignature() -> FunctionSignatureSyntax {
        #if canImport(SwiftSyntax600)
        FunctionSignatureSyntax(
            parameterClause: .init(parameters: []),
            effectSpecifiers: FunctionEffectSpecifiersSyntax(
                throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))),
            returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: bindings))
        )
        #else
        FunctionSignatureSyntax(
            parameterClause: .init(parameters: []),
            effectSpecifiers: FunctionEffectSpecifiersSyntax(throwsSpecifier: .keyword(.throws)),
            returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: bindings))
        )
        #endif
    }

    private static func decodeRow(from columns: [Column]) -> FunctionDeclSyntax {
        return FunctionDeclSyntax(
            name: .identifier("decodeRow"),
            signature: decodeRowFunctionSignature(),
            body: CodeBlockSyntax(statementsBuilder: {
                if !columns.isEmpty {
                    CodeBlockItemSyntax(item: .decl(DeclSyntax(
                        VariableDeclSyntax(
                            bindingSpecifier: .keyword(.let),
                            bindings: [
                                PatternBindingSyntax(
                                    pattern: TuplePatternSyntax(elementsBuilder: {
                                        for (column, _, _, alias) in columns {
                                            TuplePatternElementSyntax(pattern: IdentifierPatternSyntax(identifier: .identifier(alias ?? column)))
                                        }
                                    }),
                                    initializer: InitializerClauseSyntax(
                                        value: TryExprSyntax(
                                            expression: FunctionCallExprSyntax(
                                                calledExpression: MemberAccessExprSyntax(
                                                    base: DeclReferenceExprSyntax(baseName: .identifier("row")),
                                                    name: .identifier("decode")
                                                ),
                                                leftParen: .leftParenToken(),
                                                rightParen: .rightParenToken(),
                                                argumentsBuilder: {
                                                    LabeledExprSyntax(expression: MemberAccessExprSyntax(
                                                        base: TupleExprSyntax(elementsBuilder: {
                                                            for (_, column, isOptional, _) in columns {
                                                                makeTypeExpressionSyntax(for: column, optional: isOptional)
                                                            }
                                                        }),
                                                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                                                    ))
                                                }
                                            )
                                        )
                                    )
                                )
                            ]
                        )
                    )))
                    CodeBlockItemSyntax(item: .stmt(StmtSyntax(ReturnStmtSyntax(expression: FunctionCallExprSyntax(
                        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("Row")),
                        leftParen: .leftParenToken(),
                        rightParen: .rightParenToken(),
                        argumentsBuilder: {
                            for (column, _, _, alias) in columns {
                                LabeledExprSyntax(
                                    label: alias ?? column,
                                    expression: DeclReferenceExprSyntax(baseName: .identifier(alias ?? column))
                                )
                            }
                        }
                    )))))
                }
            })
        )
    }

    private static func decodeRowFunctionSignature() -> FunctionSignatureSyntax {
        #if canImport(SwiftSyntax600)
        FunctionSignatureSyntax(
            parameterClause: .init(parameters: [
                FunctionParameterSyntax(
                    firstName: .wildcardToken(),
                    secondName: .identifier("row"),
                    type: TypeSyntax(stringLiteral: row)
                )
            ]),
            effectSpecifiers: FunctionEffectSpecifiersSyntax(
                throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
            ),
            returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "Row"))
        )
        #else
        FunctionSignatureSyntax(
            parameterClause: .init(parameters: [
                FunctionParameterSyntax(
                    firstName: .wildcardToken(),
                    secondName: .identifier("row"),
                    type: TypeSyntax(stringLiteral: row)
                )
            ]),
            effectSpecifiers: FunctionEffectSpecifiersSyntax(
                throwsSpecifier: .keyword(.throws)
            ),
            returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "Row"))
        )
        #endif
    }

    private static func makeTypeExpressionSyntax(for type: TokenSyntax, optional: Bool) -> LabeledExprSyntax {
        if optional {
            LabeledExprSyntax(expression: OptionalChainingExprSyntax(expression: DeclReferenceExprSyntax(baseName: type)))
        } else {
            LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: type))
        }
    }

    private static func makeTypeSyntax(_ type: TokenSyntax, optional: Bool) -> TypeAnnotationSyntax {
        if optional {
            TypeAnnotationSyntax(type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: type)))
        } else {
            TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: type))
        }
    }
}
