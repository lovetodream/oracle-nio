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

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private enum StatementMacroDiagnosticMessages: DiagnosticMessage {
    case invalidDeclaration

    var diagnosticID: MessageID {
        switch self {
        case .invalidDeclaration:
            MessageID(domain: "OracleNIO", id: "statement-invalid-declaration")
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
    let fixItID = MessageID(domain: "OracleNIO", id: "statement-invalid-declaration-fix-it")
}
private enum StatementMacroError: Error, DiagnosticMessage {
    case unprocessableInterpolation(name: String, isBind: Bool)

    var diagnosticID: MessageID {
        switch self {
        case .unprocessableInterpolation:
            MessageID(domain: "OracleNIO", id: "unprocessable-interpolation")
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
        let protocols = protocols.map { InheritedTypeSyntax(type: $0) }
        return [
            ExtensionDeclSyntax(
                extendedType: type,
                inheritanceClause: .init(inheritedTypes: InheritedTypeListSyntax(protocols)),
                memberBlockBuilder: {}
            )
        ]
    }

    public static func expansion(
        of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: StatementMacroDiagnosticMessages.invalidDeclaration,
                    fixIt: FixIt(
                        message: InvalidDeclarationFixIt(introducer: declaration.introducer),
                        changes: [
                            FixIt.Change.replace(
                                oldNode: Syntax(declaration.introducer),
                                newNode: Syntax(TokenSyntax.keyword(.struct))
                            )
                        ])
                ))
            return []
        }

        // It is fine to force unwrap here, because the compiler ensures we receive this exact syntax tree here.
        let elements = node
            .arguments!.as(LabeledExprListSyntax.self)!
            .first!.expression.as(StringLiteralExprSyntax.self)!.segments

        var sql = ""
        var columns: [Column] = []
        var binds: [Bind] = []
        for element in elements {
            if let expression = element.as(ExpressionSegmentSyntax.self) {
                let interpolation = try extractInterpolations(expression)
                switch interpolation {
                case .column(let column):
                    columns.append(column)
                    sql.append(column.name)
                    if let alias = column.alias {
                        sql.append(" AS \(alias)")
                    }
                case .bind(let bind):
                    binds.append(bind)
                    sql.append(":\(binds.count)")
                }
            } else if let expression = element.as(StringSegmentSyntax.self) {
                sql.append(expression.content.text)
            }
        }

        let rowDeclaration: DeclSyntax
        if columns.isEmpty {
            let rowAlias = TypeAliasDeclSyntax(
                name: .identifier("Row"),
                initializer: TypeInitializerClauseSyntax(
                    value: IdentifierTypeSyntax(name: .identifier("Void"))))
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
                initializer: InitializerClauseSyntax(value: StringLiteralExprSyntax(content: sql))
            )
        }

        let bindings = binds.map { name, type, isOptional in
            VariableDeclSyntax(
                bindingSpecifier: .keyword(
                    .var, leadingTrivia: .carriageReturnLineFeed, trailingTrivia: .space),
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
            DeclSyntax(decodeRow),
        ]
    }

    private enum Interpolation {
        case column(Column)
        case bind(Bind)
    }
    private static func extractInterpolations(_ node: ExpressionSegmentSyntax) throws
        -> Interpolation
    {
        let tupleElements = node.expressions
        precondition(
            tupleElements.count >= 2,
            "Expected tuple with two or more elements, less are impossible as the compiler already checks for it"
        )

        // First element needs to be the column name
        var iterator = tupleElements.makeIterator()
        let identifier = iterator.next()! as LabeledExprSyntax  // works as tuple contains at least two elements
        // Type can be force-unwrapped as the compiler ensures it is there.
        let rawType = iterator.next()!.expression.as(MemberAccessExprSyntax.self)!.base!
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
                isBind: identifier.label?.identifier?.name == "bind"
            )
        }
        // Same thing as with type.
        let name = identifier.expression.as(StringLiteralExprSyntax.self)!
            .segments.first!.as(StringSegmentSyntax.self)!.content.text
        switch identifier.label?.identifier?.name {
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
                                        pattern: IdentifierPatternSyntax(
                                            identifier: .identifier(alias ?? name)),
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
            signature: FunctionSignatureSyntax(
                parameterClause: .init(parameters: []),
                effectSpecifiers: FunctionEffectSpecifiersSyntax(
                    throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))),
                returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "OracleBindings"))
            ),
            body: CodeBlockSyntax(statementsBuilder: {
                CodeBlockItemSyntax(
                    item: .decl(
                        DeclSyntax(
                            VariableDeclSyntax(
                                bindingSpecifier: .keyword(.var),
                                bindings: PatternBindingListSyntax(itemsBuilder: {
                                    PatternBindingSyntax(
                                        pattern: IdentifierPatternSyntax(
                                            identifier: .identifier("bindings")),
                                        initializer: InitializerClauseSyntax(
                                            value: FunctionCallExprSyntax(
                                                calledExpression: DeclReferenceExprSyntax(
                                                    baseName: .identifier("OracleBindings")),
                                                leftParen: .leftParenToken(),
                                                arguments: [
                                                    LabeledExprSyntax(
                                                        label: "capacity",
                                                        expression: IntegerLiteralExprSyntax(
                                                            binds.count)
                                                    )
                                                ],
                                                rightParen: .rightParenToken()
                                            ))
                                    )
                                })
                            )
                        ))
                )
                for (index, (bind, _, _)) in binds.enumerated() {
                    CodeBlockItemSyntax(
                        item: .expr(
                            ExprSyntax(
                                FunctionCallExprSyntax(
                                    calledExpression: MemberAccessExprSyntax(
                                        base: DeclReferenceExprSyntax(
                                            baseName: .identifier("bindings")),
                                        declName: DeclReferenceExprSyntax(
                                            baseName: .identifier("append"))
                                    ),
                                    leftParen: .leftParenToken(),
                                    arguments: [
                                        LabeledExprSyntax(
                                            label: nil,
                                            expression: DeclReferenceExprSyntax(
                                                baseName: .identifier(bind)),
                                            trailingComma: .commaToken()),
                                        LabeledExprSyntax(
                                            label: "context", colon: .colonToken(),
                                            expression: MemberAccessExprSyntax(name: "default"),
                                            trailingComma: .commaToken()),
                                        LabeledExprSyntax(
                                            label: "bindName",
                                            expression: StringLiteralExprSyntax(
                                                content: "\(index + 1)")),
                                    ],
                                    rightParen: .rightParenToken()
                                )
                            )))
                }
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ReturnStmtSyntax(
                                expression: DeclReferenceExprSyntax(
                                    baseName: .identifier("bindings"))
                            ))))
            })
        )
    }

    private static func makeEmptyBindings() -> FunctionDeclSyntax {
        FunctionDeclSyntax(
            name: .identifier("makeBindings"),
            signature: FunctionSignatureSyntax(
                parameterClause: .init(parameters: []),
                effectSpecifiers: FunctionEffectSpecifiersSyntax(
                    throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))),
                returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "OracleBindings"))
            ),
            body: CodeBlockSyntax(statementsBuilder: {
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ReturnStmtSyntax(
                                expression: FunctionCallExprSyntax(
                                    calledExpression: DeclReferenceExprSyntax(
                                        baseName: .identifier("OracleBindings")),
                                    leftParen: .leftParenToken(),
                                    arguments: [],
                                    rightParen: .rightParenToken()
                                ))
                        ))
                )
            })
        )
    }

    private static func decodeRow(from columns: [Column]) -> FunctionDeclSyntax {
        FunctionDeclSyntax(
            name: .identifier("decodeRow"),
            signature: FunctionSignatureSyntax(
                parameterClause: .init(parameters: [
                    FunctionParameterSyntax(
                        firstName: .wildcardToken(),
                        secondName: .identifier("row"),
                        type: TypeSyntax(stringLiteral: "OracleRow")
                    )
                ]),
                effectSpecifiers: FunctionEffectSpecifiersSyntax(
                    throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
                ),
                returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "Row"))
            ),
            body: CodeBlockSyntax(statementsBuilder: {
                if !columns.isEmpty {
                    CodeBlockItemSyntax(
                        item: .decl(
                            DeclSyntax(
                                VariableDeclSyntax(
                                    bindingSpecifier: .keyword(.let),
                                    bindings: [
                                        PatternBindingSyntax(
                                            pattern: TuplePatternSyntax(elementsBuilder: {
                                                for (column, _, _, alias) in columns {
                                                    TuplePatternElementSyntax(
                                                        pattern: IdentifierPatternSyntax(
                                                            identifier: .identifier(alias ?? column)
                                                        ))
                                                }
                                            }),
                                            initializer: InitializerClauseSyntax(
                                                value: TryExprSyntax(
                                                    expression: FunctionCallExprSyntax(
                                                        calledExpression: MemberAccessExprSyntax(
                                                            base: DeclReferenceExprSyntax(
                                                                baseName: .identifier("row")),
                                                            name: .identifier("decode")
                                                        ),
                                                        leftParen: .leftParenToken(),
                                                        rightParen: .rightParenToken(),
                                                        argumentsBuilder: {
                                                            LabeledExprSyntax(
                                                                expression: MemberAccessExprSyntax(
                                                                    base: TupleExprSyntax(
                                                                        elementsBuilder: {
                                                                            for (
                                                                                _, column,
                                                                                isOptional, _
                                                                            )
                                                                                in columns
                                                                            {
                                                                                makeTypeExpressionSyntax(
                                                                                    for: column,
                                                                                    optional:
                                                                                        isOptional)
                                                                            }
                                                                        }),
                                                                    declName:
                                                                        DeclReferenceExprSyntax(
                                                                            baseName: .keyword(
                                                                                .self))
                                                                ))
                                                        }
                                                    )
                                                )
                                            )
                                        )
                                    ]
                                )
                            )))
                    CodeBlockItemSyntax(
                        item: .stmt(
                            StmtSyntax(
                                ReturnStmtSyntax(
                                    expression: FunctionCallExprSyntax(
                                        calledExpression: DeclReferenceExprSyntax(
                                            baseName: .identifier("Row")),
                                        leftParen: .leftParenToken(),
                                        rightParen: .rightParenToken(),
                                        argumentsBuilder: {
                                            for (column, _, _, alias) in columns {
                                                LabeledExprSyntax(
                                                    label: alias ?? column,
                                                    expression: DeclReferenceExprSyntax(
                                                        baseName: .identifier(alias ?? column))
                                                )
                                            }
                                        }
                                    )))))
                }
            })
        )
    }

    private static func makeTypeExpressionSyntax(for type: TokenSyntax, optional: Bool)
        -> LabeledExprSyntax
    {
        if optional {
            LabeledExprSyntax(
                expression: OptionalChainingExprSyntax(
                    expression: DeclReferenceExprSyntax(baseName: type)))
        } else {
            LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: type))
        }
    }

    private static func makeTypeSyntax(_ type: TokenSyntax, optional: Bool) -> TypeAnnotationSyntax
    {
        if optional {
            TypeAnnotationSyntax(
                type: OptionalTypeSyntax(wrappedType: IdentifierTypeSyntax(name: type)))
        } else {
            TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: type))
        }
    }
}
