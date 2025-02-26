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

@testable import OracleNIO

extension Capabilities {
    static func desired(supportsOOB: Bool = false) -> Capabilities {
        var caps = Capabilities()
        caps.protocolVersion = Constants.TNS_VERSION_DESIRED
        caps.protocolOptions = supportsOOB ? Constants.TNS_GSO_CAN_RECV_ATTENTION : caps.protocolOptions
        caps.supportsFastAuth = true
        caps.supportsOOB = supportsOOB
        return caps
    }
}
