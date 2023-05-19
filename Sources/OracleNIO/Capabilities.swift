//
//  Capabilities.swift
//  OracleNIO
//
//  Created by Timo Zacherl on 05.01.23.
//
//  Defining the capabilities (negotiated at connect time) that both
//  the database server and the client are capable of.
//

struct Capabilities {
    var protocolVersion: UInt16 = 0
    var charsetID = Constants.TNS_CHARSET_UTF8
    var nCharsetID = Constants.TNS_CHARSET_UTF16
    var compileCapabilities = [UInt8](repeating: 0, count: Constants.TNS_CCAP_MAX)
    var runtimeCapabilities = [UInt8](repeating: 0, count: Constants.TNS_RCAP_MAX)
    var characterConversion = false
    var supportsOOB = false
    var maxStringSize: UInt32 = 0

    // MARK: Compile Capabilities
    var ttcFieldVersion: UInt8 = Constants.TNS_CCAP_FIELD_VERSION_MAX

    init() {
        // Compile Capabilities
        self.compileCapabilities[Constants.TNS_CCAP_SQL_VERSION] = Constants.TNS_CCAP_SQL_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_LOGON_TYPES] =
            Constants.TNS_CCAP_O5LOGON | Constants.TNS_CCAP_O5LOGON_NP |
            Constants.TNS_CCAP_O7LOGON | Constants.TNS_CCAP_O8LOGON_LONG_IDENTIFIER
        self.compileCapabilities[Constants.TNS_CCAP_FIELD_VERSION] = self.ttcFieldVersion
        self.compileCapabilities[Constants.TNS_CCAP_SERVER_DEFINE_CONV] = 1
        self.compileCapabilities[Constants.TNS_CCAP_TTC1] =
            Constants.TNS_CCAP_FAST_BVEC | Constants.TNS_CCAP_END_OF_CALL_STATUS | Constants.TNS_CCAP_IND_RCD
        self.compileCapabilities[Constants.TNS_CCAP_OCI1] =
            Constants.TNS_CCAP_FAST_SESSION_PROPAGATE | Constants.TNS_CCAP_APP_CTX_PIGGYBACK
        self.compileCapabilities[Constants.TNS_CCAP_TDS_VERSION] = Constants.TNS_CCAP_TDS_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_RPC_VERSION] = Constants.TNS_CCAP_RPC_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_RPC_SIG] = Constants.TNS_CCAP_RPC_SIG_VALUE
        self.compileCapabilities[Constants.TNS_CCAP_DBF_VERSION] = Constants.TNS_CCAP_DBF_VERSION_MAX
        self.compileCapabilities[Constants.TNS_CCAP_LOB] = Constants.TNS_CCAP_LOB_UB8_SIZE | Constants.TNS_CCAP_LOB_ENCS
        self.compileCapabilities[Constants.TNS_CCAP_UB2_DTY] = 1
        self.compileCapabilities[Constants.TNS_CCAP_TTC3] =
            Constants.TNS_CCAP_IMPLICIT_RESULTS | Constants.TNS_CCAP_BIG_CHUNK_CLR | Constants.TNS_CCAP_KEEP_OUT_ORDER
        self.compileCapabilities[Constants.TNS_CCAP_TTC2] = Constants.TNS_CCAP_ZLNP
        self.compileCapabilities[Constants.TNS_CCAP_OCI2] = Constants.TNS_CCAP_DRCP
        self.compileCapabilities[Constants.TNS_CCAP_CLIENT_FN] = Constants.TNS_CCAP_CLIENT_FN_MAX
        self.compileCapabilities[Constants.TNS_CCAP_TTC4] = Constants.TNS_CCAP_INBAND_NOTIFICATION

        // Runtime Capabilities
        self.runtimeCapabilities[Constants.TNS_RCAP_COMPAT] = Constants.TNS_RCAP_COMPAT_81
        self.runtimeCapabilities[Constants.TNS_RCAP_TTC] = Constants.TNS_RCAP_TTC_ZERO_COPY | Constants.TNS_RCAP_TTC_32K
    }

    mutating func adjustForProtocol(version: UInt16, options: UInt16) {
        self.protocolVersion = version
        self.supportsOOB = options & Constants.TNS_GSO_CAN_RECV_ATTENTION != 0
    }

    mutating func adjustForServerCompileCapabilities(_ serverCapabilities: [UInt8]) {
        if serverCapabilities[Constants.TNS_CCAP_FIELD_VERSION] < self.ttcFieldVersion {
            self.ttcFieldVersion = serverCapabilities[Constants.TNS_CCAP_FIELD_VERSION]
            self.compileCapabilities[Constants.TNS_CCAP_FIELD_VERSION] = self.ttcFieldVersion
        }
    }

    mutating func adjustForServerRuntimeCapabilities(_ serverCapabilities: [UInt8]) {
        if (serverCapabilities[Constants.TNS_RCAP_TTC] & Constants.TNS_RCAP_TTC_32K) != 0 {
            self.maxStringSize = 32767
        } else {
            self.maxStringSize = 4000
        }
    }

    func checkNCharsetID() throws {
        if self.nCharsetID != Constants.TNS_CHARSET_UTF16 {
            throw OracleError.ErrorType.nCharCSNotSupported
        }
    }
}
