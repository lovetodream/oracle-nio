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

import NIOCore

extension ByteBuffer {
    var oracleColumnIsEmpty: Bool {
        self.readableBytes == 1
            && [0, Constants.TNS_NULL_LENGTH_INDICATOR].contains(
                self.getInteger(at: self.readerIndex, as: UInt8.self))
    }
}
