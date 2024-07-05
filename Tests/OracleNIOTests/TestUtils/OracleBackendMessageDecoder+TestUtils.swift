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

@testable import OracleNIO

extension OracleBackendMessageDecoder.Context {
    convenience init(
        capabilities: Capabilities = Capabilities(),
        statementContext: StatementContext = StatementContext(statement: ""),
        columns: OracleDataType...
    ) {
        self.init(capabilities: capabilities)
        self.statementContext = statementContext
        var describeInfo = DescribeInfo(columns: [])
        for column in columns {
            describeInfo.columns.append(
                .init(
                    name: "",
                    dataType: column,
                    dataTypeSize: UInt32(column.defaultSize),
                    precision: 0,
                    scale: 0,
                    bufferSize: 1,
                    nullsAllowed: true,
                    typeScheme: nil,
                    typeName: nil,
                    domainSchema: nil,
                    domainName: nil,
                    annotations: [:],
                    vectorDimensions: nil,
                    vectorFormat: nil
                ))
        }
        self.describeInfo = describeInfo
    }
}
