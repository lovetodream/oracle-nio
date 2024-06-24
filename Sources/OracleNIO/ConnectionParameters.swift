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

struct Address: Equatable {
    var `protocol`: OracleConnection.Configuration.OracleProtocol
    var host: String
    var port: Int

    func buildConnectString() -> String {
        let parts = [
            "(PROTOCOL=\(self.protocol.description))",
            "(HOST=\(self.host))",
            "(PORT=\(self.port))",
        ]
        return "(ADDRESS=\(parts.joined()))"
    }
}

struct AddressList: Equatable {
    var addresses: [Address] = []

    func usesTCPS() -> Bool {
        self.addresses.contains { $0.protocol == .tcps }
    }

    func buildConnectString() -> String {
        let parts = self.addresses.map { $0.buildConnectString() }
        if parts.count == 1 {
            return parts[0]
        }
        return "(ADDRESS_LIST=\(parts.joined())"
    }
}

struct Description: Equatable {
    var connectionID: String

    var addressLists: [AddressList]
    var sourceRoute: Bool = false
    var loadBalance: Bool = false
    var expireTime: Int = 0
    var retryCount: Int = 0
    var retryDelay: Int = 0
    var tcpConnectTimeout: TimeAmount = .seconds(10)
    var service: OracleServiceMethod
    var sslServerDnMatch: Bool
    var sslServerCertDn: String?
    var walletLocation: String?
    var purity: Purity
    var serverType: String?  // when using drcp: "pooled"
    var cclass: String?

    private func buildDurationString(_ value: TimeAmount) -> String {
        let value = Int(
            value.nanoseconds / TimeAmount.milliseconds(1).nanoseconds
        )
        return "\(value)ms"
    }

    func buildConnectString(_ cid: String?) -> String {
        var usesTCPS = false

        // build the top-level description parts
        var parts = [String]()
        if self.loadBalance {
            parts.append("(LOAD_BALANCE=ON)")
        }
        if self.sourceRoute {
            parts.append("(SOURCE_ROUTE=ON)")
        }
        if self.retryCount != 0 {
            parts.append("(RETRY_COUNT=\(self.retryCount))")
        }
        if self.retryDelay != 0 {
            parts.append("(RETRY_DELAY=\(self.retryDelay))")
        }
        if self.expireTime != 0 {
            parts.append("(EXPIRE_TIME=\(self.expireTime))")
        }
        if self.tcpConnectTimeout != .seconds(10) {
            let temp = self.buildDurationString(self.tcpConnectTimeout)
            parts.append("(TRANSPORT_CONNECT_TIMEOUT=\(temp))")
        }

        // add address lists, but if the address list contains only a single
        // entry and that entry does not have a host, the other parts aren't
        // relevant anyway!
        for addressList in self.addressLists {
            let temp = addressList.buildConnectString()
            parts.append(temp)
            if !usesTCPS {
                usesTCPS = addressList.usesTCPS()
            }
        }

        // build connect data segment
        var tempParts = [String]()
        switch self.service {
        case .serviceName(let serviceName):
            tempParts.append("(SERVICE_NAME=\(serviceName))")
        case .sid(let sid):
            tempParts.append("(SID=\(sid))")
        }
        if let serverType {
            tempParts.append("(SERVER=\(serverType))")
        }
        if let cid {
            tempParts.append("(CID=\(cid))")
        } else {
            if let cclass {
                tempParts.append("(POOL_CONNECTION_CLASS=\(cclass)")
            }
            if self.purity != .default {
                tempParts.append("(POOL_PURITY=\(self.purity.rawValue))")
            }
        }
        if !self.connectionID.isEmpty {
            tempParts.append("(CONNECTION_ID=\(self.connectionID))")
        }
        if !tempParts.isEmpty {
            parts.append("(CONNECT_DATA=\(tempParts.joined()))")
        }

        // build security segment, if applicable
        if usesTCPS {
            tempParts = []
            if self.sslServerDnMatch {
                tempParts.append("(SSL_SERVER_DN_MATCH=ON)")
            }
            if let sslServerCertDn {
                let temp = "(SSL_SERVER_CERT_DN=\(sslServerCertDn))"
                tempParts.append(temp)
            }
            if let walletLocation {
                let temp = "(MY_WALLET_DIRECTORY=\(walletLocation))"
                tempParts.append(temp)
            }
            parts.append("(SECURITY=\(tempParts.joined()))")
        }

        return "(DESCRIPTION=\(parts.joined()))"
    }
}
