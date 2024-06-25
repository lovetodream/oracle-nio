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

/// Defining the capabilities (negotiated at connect time) that both
/// the database server and the client are capable of.
struct Capabilities: Sendable, Hashable {
    var protocolVersion: UInt16 = 0
    var protocolOptions: UInt16 = 0
    var charsetID = Constants.TNS_CHARSET_UTF8
    var nCharsetID = Constants.TNS_CHARSET_UTF16
    var compileCapabilities = [UInt8](repeating: 0, count: Constants.TNS_CCAP_MAX)
    var runtimeCapabilities = [UInt8](repeating: 0, count: Constants.TNS_RCAP_MAX)
    var supportsFastAuth = false
    var supportsOOB = false
    var supportsEndOfRequest = false
    var maxStringSize: UInt32 = 0
    var sdu: UInt32 = UInt32(Constants.TNS_SDU)

    // MARK: Compile Capabilities
    var ttcFieldVersion: UInt8 = Constants.TNS_CCAP_FIELD_VERSION_MAX

    init() {
        // Compile Capabilities
        self.compileCapabilities[Constants.TNS_CCAP_SQL_VERSION] =
            Constants.TNS_CCAP_SQL_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_LOGON_TYPES] =
            Constants.TNS_CCAP_O5LOGON | Constants.TNS_CCAP_O5LOGON_NP | Constants.TNS_CCAP_O7LOGON
            | Constants.TNS_CCAP_O8LOGON_LONG_IDENTIFIER | Constants.TNS_CCAP_O9LOGON_LONG_PASSWORD
        self.compileCapabilities[Constants.TNS_CCAP_FEATURE_BACKPORT] =
            Constants.TNS_CCAP_CTB_IMPLICIT_POOL
        self.compileCapabilities[Constants.TNS_CCAP_FIELD_VERSION] = self.ttcFieldVersion
        self.compileCapabilities[Constants.TNS_CCAP_SERVER_DEFINE_CONV] = 1
        self.compileCapabilities[Constants.TNS_CCAP_TTC1] =
            Constants.TNS_CCAP_FAST_BVEC | Constants.TNS_CCAP_END_OF_CALL_STATUS
            | Constants.TNS_CCAP_IND_RCD
        self.compileCapabilities[Constants.TNS_CCAP_OCI1] =
            Constants.TNS_CCAP_FAST_SESSION_PROPAGATE | Constants.TNS_CCAP_APP_CTX_PIGGYBACK
        self.compileCapabilities[Constants.TNS_CCAP_TDS_VERSION] =
            Constants.TNS_CCAP_TDS_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_RPC_VERSION] =
            Constants.TNS_CCAP_RPC_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_RPC_SIG] = Constants.TNS_CCAP_RPC_SIG_VALUE
        self.compileCapabilities[Constants.TNS_CCAP_DBF_VERSION] =
            Constants.TNS_CCAP_DBF_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_LOB] =
            Constants.TNS_CCAP_LOB_UB8_SIZE | Constants.TNS_CCAP_LOB_ENCS
            | Constants.TNS_CCAP_LOB_PREFETCH_LENGTH | Constants.TNS_CCAP_LOB_TEMP_SIZE
            | Constants.TNS_CCAP_LOB_12C | Constants.TNS_CCAP_LOB_PREFETCH_DATA
        self.compileCapabilities[Constants.TNS_CCAP_UB2_DTY] = 1
        self.compileCapabilities[Constants.TNS_CCAP_LOB2] =
            Constants.TNS_CCAP_LOB2_QUASI | Constants.TNS_CCAP_LOB2_2GB_PREFETCH
        self.compileCapabilities[Constants.TNS_CCAP_TTC3] =
            Constants.TNS_CCAP_IMPLICIT_RESULTS | Constants.TNS_CCAP_BIG_CHUNK_CLR
            | Constants.TNS_CCAP_KEEP_OUT_ORDER
        self.compileCapabilities[Constants.TNS_CCAP_TTC2] = Constants.TNS_CCAP_ZLNP
        self.compileCapabilities[Constants.TNS_CCAP_OCI2] = Constants.TNS_CCAP_DRCP
        self.compileCapabilities[Constants.TNS_CCAP_CLIENT_FN] = Constants.TNS_CCAP_CLIENT_FN_MAX
        self.compileCapabilities[Constants.TNS_CCAP_TTC4] = Constants.TNS_CCAP_INBAND_NOTIFICATION
        self.compileCapabilities[Constants.TNS_CCAP_TTC5] = Constants.TNS_CCAP_VECTOR_SUPPORT

        // Runtime Capabilities
        self.runtimeCapabilities[Constants.TNS_RCAP_COMPAT] = Constants.TNS_RCAP_COMPAT_81
        self.runtimeCapabilities[Constants.TNS_RCAP_TTC] =
            Constants.TNS_RCAP_TTC_ZERO_COPY | Constants.TNS_RCAP_TTC_32K
    }

    /// Decodes Capabilities from a buffer created with ``encode(into:)``.
    init(from buffer: inout ByteBuffer) throws {
        self.protocolVersion = try buffer.throwingReadInteger()
        self.protocolOptions = try buffer.throwingReadInteger()
        self.charsetID = try buffer.throwingReadInteger()
        self.nCharsetID = try buffer.throwingReadInteger()
        self.compileCapabilities = .init(repeating: 0, count: Constants.TNS_CCAP_MAX)
        self.runtimeCapabilities = .init(repeating: 0, count: Constants.TNS_RCAP_MAX)
        self.supportsFastAuth = try buffer.throwingReadInteger(as: UInt8.self) == 1
        self.supportsOOB = try buffer.throwingReadInteger(as: UInt8.self) == 1
        self.supportsEndOfRequest = try buffer.throwingReadInteger(as: UInt8.self) == 1
        self.maxStringSize = try buffer.throwingReadInteger()
        self.sdu = try buffer.throwingReadInteger()
        self.ttcFieldVersion = try buffer.throwingReadInteger()
    }

    /// Encodes all the properties of capabilities except the runtime and compile time capabilities.
    func encode(into buffer: inout ByteBuffer) throws {
        buffer.writeInteger(self.protocolVersion)
        buffer.writeInteger(self.protocolOptions)
        buffer.writeInteger(self.charsetID)
        buffer.writeInteger(self.nCharsetID)
        buffer.writeInteger(UInt8(self.supportsFastAuth ? 1 : 0))
        buffer.writeInteger(UInt8(self.supportsOOB ? 1 : 0))
        buffer.writeInteger(UInt8(self.supportsEndOfRequest ? 1 : 0))
        buffer.writeInteger(self.maxStringSize)
        buffer.writeInteger(self.sdu)
        buffer.writeInteger(self.ttcFieldVersion)
    }

    mutating func adjustForProtocol(version: UInt16, options: UInt16, flags: UInt32) {
        self.protocolVersion = version
        self.protocolOptions = options
        self.supportsOOB = options & Constants.TNS_GSO_CAN_RECV_ATTENTION != 0
        if (flags & Constants.TNS_ACCEPT_FLAG_FAST_AUTH) != 0 {
            self.supportsFastAuth = true
        }
        if self.protocolVersion >= Constants.TNS_VERSION_MIN_END_OF_RESPONSE
            && (flags & Constants.TNS_ACCEPT_FLAG_HAS_END_OF_REQUEST) != 0
        {
            self.compileCapabilities[Constants.TNS_CCAP_TTC4] |=
                Constants.TNS_CCAP_END_OF_REQUEST
            self.supportsEndOfRequest = true
        }
    }

    mutating func adjustForServerCompileCapabilities(
        _ serverCapabilities: ByteBuffer
    ) {
        let ttcFieldVersion =
            serverCapabilities
            .getInteger(
                at: Constants.TNS_CCAP_FIELD_VERSION, as: UInt8.self
            )
        if let ttcFieldVersion, ttcFieldVersion < self.ttcFieldVersion {
            self.ttcFieldVersion = ttcFieldVersion
            self.compileCapabilities[Constants.TNS_CCAP_FIELD_VERSION] =
                self.ttcFieldVersion
        }
        if self.ttcFieldVersion < Constants.TNS_CCAP_FIELD_VERSION_23_4
            && self.supportsEndOfRequest
        {
            self.compileCapabilities[Constants.TNS_CCAP_TTC4] ^=
                Constants.TNS_CCAP_END_OF_REQUEST
            self.supportsEndOfRequest = false
        }
    }

    mutating func adjustForServerRuntimeCapabilities(
        _ serverCapabilities: ByteBuffer
    ) {
        let rcapTTC =
            serverCapabilities
            .getInteger(at: Constants.TNS_RCAP_TTC, as: UInt8.self)
        if let rcapTTC, (rcapTTC & Constants.TNS_RCAP_TTC_32K) != 0 {
            self.maxStringSize = 32767
        } else {
            self.maxStringSize = 4000
        }
    }

    func checkNCharsetID() throws {
        if ![Constants.TNS_CHARSET_UTF16, Constants.TNS_CHARSET_AL16UTF8]
            .contains(self.nCharsetID)
        {
            throw OracleSQLError.nationalCharsetNotSupported
        }
    }
}
