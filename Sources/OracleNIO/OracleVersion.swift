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

/// Oracle Release Number Format:
/// ```
/// 12.1.0.1.0
///  ┬ ┬ ┬ ┬ ┬
///  │ │ │ │ └───── Platform-Specific Release Number
///  │ │ │ └────────── Component-Specific Release Number
///  │ │ └─────────────── Fusion Middleware Release Number
///  │ └──────────────────── Database Maintenance Release Number
///  └───────────────────────── Major Database Release Number
///  ```
public struct OracleVersion: CustomStringConvertible, Sendable {
    public let majorDatabaseReleaseNumber: Int
    public let databaseMaintenanceReleaseNumber: Int
    public let fusionMiddlewareReleaseNumber: Int
    public let componentSpecificReleaseNumber: Int
    public let platformSpecificReleaseNumber: Int

    public var description: String {
        """
        \(majorDatabaseReleaseNumber).\(databaseMaintenanceReleaseNumber).\
        \(fusionMiddlewareReleaseNumber).\(componentSpecificReleaseNumber).\
        \(platformSpecificReleaseNumber)
        """
    }
}
