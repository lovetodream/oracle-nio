//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

@testable import OracleNIO

extension OracleBackendMessage.RowData {
    init<T: OracleEncodable>(_ elements: T...) {
        var columns: [OracleBackendMessage.RowData.ColumnStorage] = []
        for element in elements {
            var buffer = ByteBuffer()
            element._encodeRaw(into: &buffer, context: .default)
            columns.append(.data(buffer))
        }
        self.init(columns: columns)
    }
}

extension BackendError {
    static let noData = BackendError(
        number: 1403,
        cursorID: 1,
        position: 20,
        rowCount: 1,
        isWarning: false,
        message: "ORA-01403: no data found\n",
        rowID: nil,
        batchErrors: []
    )

    static let sendFetch = BackendError(
        number: 0,
        cursorID: 3,
        position: 0,
        rowCount: 2,
        isWarning: false,
        message: nil,
        rowID: nil,
        batchErrors: []
    )

    static func userRequestedCancel(cursorID: UInt16 = 1) -> BackendError {
        BackendError(
            number: 1013,
            cursorID: cursorID,
            position: 0,
            rowCount: 0,
            isWarning: false,
            message: "ORA-01013: User requested cancel of current operation.",
            rowID: nil,
            batchErrors: []
        )
    }
}
