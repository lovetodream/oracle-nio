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
    var supportsOOB = false

    init() {}

    mutating func adjustForProtocol(version: UInt16, options: UInt16) {
        self.protocolVersion = version
        self.supportsOOB = options & Constants.TNS_CAN_RECV_ATTENTION != 0
    }
}

//
//class Capabilities {
//    var protocolVersion: UInt16
//    var ttcFieldVersion: UInt8
//    var charsetID: UInt16
//    var nCharsetID: UInt16
//    var compileCapabilities: [UInt8]
//    var runtimeCapabilities: [UInt8]
//    var characterConversion: Bool
//    var supportsOOB: Bool
//
//    init() {
//        self.initializeCompileCapabilities()
//        self.initializeRuntimeCapabilities()
//    }
//
//    func initializeCompileCapabilities() {
//        self.ttcFieldVersion = Constants.TNS_CCAP_FIELD_VERSION_MAX
//        self.compileCapabilities = .init(repeating: 0, count: Constants.TNS_CCAP_MAX)
//        self.compileCapabilities[Constants.TNS_CCAP_SQL_VERSION] = Constants.TNS_CCAP_SQL_VERSION_MAX
//        self.compileCapabilities[Constants.TNS_CCAP_LOGON_TYPES] = Constants.TNS_CCAP_O5LOGON | Constants.TNS_CCAP_O5LOGON_NP | Constants.TNS_CCAP_O7LOGON | Constants.TNS_CCAP_O8LOGON_LONG_IDENTIFIER
//        self.compileCapabilities[Constants.TNS_CCAP_FIELD_VERSION] = self.ttcFieldVersion
//        self.compileCapabilities[Constants.TNS_CCAP_SERVER_DEFINE_CONV] = 1
//        self.compileCapabilities[Constants.TNS_CCAP_TTC1] = Constants.TNS_CCAP_FAST_BVEC | Constants.TNS_CCAP_END_OF_CALL_STATUS | Constants.TNS_CCAP_IND_RCD
//        self.compileCapabilities[Constants.TNS_CCAP_OCI1] = Constants.TNS_CCAP_FAST_SESSION_PROPAGATE | Constants.TNS_CCAP_APP_CTX_PIGGYBACK
//        self.compileCapabilities[Constants.TNS_CCAP_TDS_VERSION] = Constants.TNS_CCAP_TDS_VERSION_MAX
//        self.compileCapabilities[Constants.TNS_CCAP_RPC_VERSION] = Constants.TNS_CCAP_RPC_VERSION_MAX
//        self.compileCapabilities[Constants.TNS_CCAP_RPC_SIG] = Constants.TNS_CCAP_RPC_SIG_VALUE
//        self.compileCapabilities[Constants.TNS_CCAP_DBF_VERSION] = Constants.TNS_CCAP_DBF_VERSION_MAX
//        self.compileCapabilities[Constants.TNS_CCAP_LOB] = Constants.TNS_CCAP_LOB_UB8_SIZE | Constants.TNS_CCAP_LOB_ENCS
//        self.compileCapabilities[Constants.TNS_CCAP_UB2_DTY] = 1
//        self.compileCapabilities[Constants.TNS_CCAP_TTC3] = Constants.TNS_CCAP_IMPLICIT_RESULTS | Constants.TNS_CCAP_BIG_CHUNK_CLR | Constants.TNS_CCAP_KEEP_OUT_ORDER
//        self.compileCapabilities[Constants.TNS_CCAP_TTC2] = Constants.TNS_CCAP_ZLNP
//        self.compileCapabilities[Constants.TNS_CCAP_OCI2] = Constants.TNS_CCAP_DRCP
//        self.compileCapabilities[Constants.TNS_CCAP_CLIENT_FN] = Constants.TNS_CCAP_CLIENT_FN_MAX
//        self.compileCapabilities[Constants.TNS_CCAP_TTC4] = Constants.TNS_CCAP_INBAND_NOTIFICATION
//    }
//
//    func initializeRuntimeCapabilities() {
//        self.runtimeCapabilities = .init(repeating: 0, count: Constants.TNS_RCAP_MAX)
//        self.runtimeCapabilities[Constants.TNS_RCAP_COMPAT] = Constants.TNS_RCAP_COMPAT_81
//        self.runtimeCapabilities[Constants.TNS_RCAP_TTC] = Constants.TNS_RCAP_TTC_ZERO_COPY | Constants.TNS_RCAP_TTC_32K
//    }
//
//    func adjustForProtocol(protocolVersion: UInt16, protocolOptions: UInt16) {
//        self.protocolVersion = protocolVersion
//        self.supportsOOB = protocolOptions & Constants.TNS_CAN_RECV_ATTENTION != 0
//    }
//
//    func adjustForServerCompileCapabilities(serverCapabilities: [UInt8]) {
//        if serverCapabilities[Constants.TNS_CCAP_FIELD_VERSION] < self.ttcFieldVersion {
//            self.ttcFieldVersion = serverCapabilities[Constants.TNS_CCAP_FIELD_VERSION]
//            self.compileCapabilities[Constants.TNS_CCAP_FIELD_VERSION] = self.ttcFieldVersion
//        }
//    }
//
//    func adjustForServerRuntimeCapabilities(serverCapabilities: [UInt8]) {}
//
//    /// Checks that the national character set id is AL16UTF16, which is the only id that is currently supported.
//    func checkNCharsetID() {
//        if self.nCharsetID != Constants.TNS_CHARSET_UTF16 {
//            fatalError("national character set id \(nCharsetID) is not supported by OracleNIO at the moment.")
//        }
//    }
//}
