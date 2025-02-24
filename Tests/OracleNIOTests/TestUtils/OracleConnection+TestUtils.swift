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

extension OracleConnection.Configuration.EndpointInfo: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.configureChannel(let lhs), .configureChannel(let rhs)):
            return lhs === rhs
        case (.connectTCP(let lhsHost, let lhsPort), .connectTCP(let rhsHost, let rhsPort)):
            return lhsHost == rhsHost && lhsPort == rhsPort
        default:
            return false
        }
    }
}
