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

// swift-format-ignore-file
import Foundation

@usableFromInline
enum Constants {

    // MARK: Packet flags
    static let TNS_PACKET_FLAG_TLS_RENEG: UInt8 = 0x08

    // MARK: Data flags
    static let TNS_DATA_FLAGS_END_OF_REQUEST: UInt16 = 0x2000
    static let TNS_DATA_FLAGS_EOF: UInt16 = 0x0040

    // MARK: Marker types
    static let TNS_MARKER_TYPE_BREAK = 1
    static let TNS_MARKER_TYPE_RESET: UInt8 = 2
    static let TNS_MARKER_TYPE_INTERRUPT = 3

    // MARK: Charset forms
    static let TNS_CS_IMPLICIT = 1
    static let TNS_CS_NCHAR = 2

    // MARK: Errors
    static let TNS_ERR_VAR_NOT_IN_SELECT_LIST = 1007
    static let TNS_ERR_INBAND_MESSAGE = 12573
    static let TNS_ERR_INVALID_SERVICE_NAME = 12514
    static let TNS_ERR_INVALID_SID = 12505
    static let TNS_ERR_NO_DATA_FOUND = 1403
    static let TNS_ERR_SESSION_SHUTDOWN = 12572
    static let TNS_ERR_ARRAY_DML_ERRORS = 24381

    // MARK: Parameter keyword numbers
    static let TNS_KEYWORD_NUM_CURRENT_SCHEMA = 168
    static let TNS_KEYWORD_NUM_EDITION = 172

    // MARK: Bind flags
    static let TNS_BIND_USE_INDICATORS: UInt8 = 0x0001
    static let TNS_BIND_ARRAY: UInt8 = 0x0040

    // MARK: Bind directions
    static let TNS_BIND_DIR_OUTPUT = 16
    static let TNS_BIND_DIR_INPUT: UInt8 = 32
    static let TNS_BIND_DIR_INPUT_OUTPUT = 48

    // MARK: Database object image flags
    static let TNS_OBJ_IS_VERSION_81 = 0x80
    static let TNS_OBJ_IS_DEGENERATE = 0x10
    static let TNS_OBJ_IS_COLLECTION = 0x08
    static let TNS_OBJ_NO_PREFIX_SEG: UInt8 = 0x04
    static let TNS_OBJ_IMAGE_VERSION = 1

    // MARK: Database object flags
    static let TNS_OBJ_MAX_SHORT_LENGTH = 245
    static let TNS_OBJ_ATOMIC_NULL = 253
    static let TNS_OBJ_NON_NULL_OID = 0x02
    static let TNS_OBJ_HAS_EXTENT_OID = 0x08
    static let TNS_OBJ_TOP_LEVEL: UInt32 = 0x01
    static let TNS_OBJ_HAS_INDEXES = 0x10

    // MARK: Database object collection types
    static let TNS_OBJ_PLSQL_INDEX_TABLE = 1
    static let TNS_OBJ_NESTED_TABLE = 2
    static let TNS_OBJ_VARRAY = 3

    // MARK: Database object TDS type codes
    static let TNS_OBJ_TDS_TYPE_CHAR = 1
    static let TNS_OBJ_TDS_TYPE_DATE = 2
    static let TNS_OBJ_TDS_TYPE_FLOAT = 5
    static let TNS_OBJ_TDS_TYPE_NUMBER = 6
    static let TNS_OBJ_TDS_TYPE_VARCHAR = 7
    static let TNS_OBJ_TDS_TYPE_BOOLEAN = 8
    static let TNS_OBJ_TDS_TYPE_RAW = 19
    static let TNS_OBJ_TDS_TYPE_TIMESTAMP = 21
    static let TNS_OBJ_TDS_TYPE_TIMESTAMP_TZ = 23
    static let TNS_OBJ_TDS_TYPE_OBJ = 27
    static let TNS_OBJ_TDS_TYPE_COLL = 28
    static let TNS_OBJ_TDS_TYPE_CLOB = 29
    static let TNS_OBJ_TDS_TYPE_BLOB = 30
    static let TNS_OBJ_TDS_TYPE_TIMESTAMP_LTZ = 33
    static let TNS_OBJ_TDS_TYPE_BINARY_FLOAT = 37
    static let TNS_OBJ_TDS_TYPE_BINARY_DOUBLE = 45

    // MARK: XML type constants
    static let TNS_XML_TYPE_LOB: UInt32 = 0x0001
    static let TNS_XML_TYPE_STRING: UInt32 = 0x0004
    static let TNS_XML_TYPE_FLAG_SKIP_NEXT_4: UInt32 = 0x100000

    // MARK: Execute options
    static let TNS_EXEC_OPTION_PARSE: UInt32 = 0x01
    static let TNS_EXEC_OPTION_BIND: UInt32 = 0x08
    static let TNS_EXEC_OPTION_DEFINE: UInt32 = 0x10
    static let TNS_EXEC_OPTION_EXECUTE: UInt32 = 0x20
    static let TNS_EXEC_OPTION_FETCH: UInt32 = 0x40
    static let TNS_EXEC_OPTION_COMMIT: UInt32 = 0x100
    static let TNS_EXEC_OPTION_COMMIT_REEXECUTE: UInt32 = 0x1
    static let TNS_EXEC_OPTION_PLSQL_BIND: UInt32 = 0x400
    static let TNS_EXEC_OPTION_DML_ROWCOUNTS: UInt32 = 0x4000
    static let TNS_EXEC_OPTION_NOT_PLSQL: UInt32 = 0x8000
    static let TNS_EXEC_OPTION_IMPLICIT_RESULTSET: UInt32 = 0x8000
    static let TNS_EXEC_OPTION_DESCRIBE: UInt32 = 0x20000
    static let TNS_EXEC_OPTION_NO_COMPRESSED_FETCH = 0x40000
    static let TNS_EXEC_OPTION_BATCH_ERRORS: UInt32 = 0x80000

    // MARK: Session return constants
    static let TNS_SESSGET_SESSION_CHANGED: UInt32 = 4

    // MARK: LOB operations
    enum LOBOperation: UInt32 {
        case getLength = 0x0001
        case read = 0x0002
        case trim = 0x0020
        case write = 0x0040
        case getChunkSize = 0x4000
        case createTemp = 0x0110
        case freeTemp = 0x0111
        case open = 0x8000
        case close = 0x10000
        case isOpen = 0x11000
        case array = 0x80000
    }

    // MARK: LOB locator constants
    static let TNS_LOB_LOCATOR_OFFSET_FLAG_1 = 4
    static let TNS_LOB_LOCATOR_OFFSET_FLAG_3 = 6
    static let TNS_LOB_LOCATOR_OFFSET_FLAG_4 = 7
    static let TNS_LOB_QLOCATOR_VERSION: UInt16 = 4
    static let TNS_LOB_LOCATOR_VAR_LENGTH_CHARSET: UInt8 = 0x80

    // MARK: Temporary and Abstract LOB constants
    static let TNS_LOB_ABSTRACT_POS = 4
    static let TNS_LOB_TEMP_POS = 7
    static let TNS_LOB_TEMP_VALUE = 0x01
    static let TNS_LOB_ABSTRACT_VALUE = 0x40

    // MARK: LOB locator flags (byte 1)
    static let TNS_LOB_LOCATOR_FLAGS_BLOB: UInt8 = 0x01
    static let TNS_LOB_LOCATOR_FLAGS_VALUE_BASED: UInt8 = 0x20
    static let TNS_LOB_LOCATOR_FLAGS_ABSTRACT: UInt8 = 0x40

    // MARK: LOB locator flags (byte 2)
    static let TNS_LOB_LOCATOR_FLAGS_INIT: UInt8 = 0x08

    // MARK: LOB locator flags (byte 4)
    static let TNS_LOB_LOCATOR_FLAGS_TEMP: UInt8 = 0x01
    static let TNS_LOB_LOCATOR_FLAGS_VAR_LENGTH_CHARSET = 0x80

    // MARK: Other LOB constants
    static let TNS_LOB_OPEN_READ_WRITE = 2
    static let TNS_LOB_PREFETCH_FLAG: UInt32 = 0x2000000

    // MARK: Base JSON constants
    static let TNS_JSON_MAX_LENGTH: UInt32 = 32 * 1024 * 1024
    static let TNS_JSON_MAGIC_BYTE_1 = 0xff
    static let TNS_JSON_MAGIC_BYTE_2 = 0x4a  // 'J'
    static let TNS_JSON_MAGIC_BYTE_3 = 0x5a  // 'Z'
    static let TNS_JSON_VERSION = 1
    static let TNS_JSON_FLAG_HASH_ID_UINT8: UInt16 = 0x0100
    static let TNS_JSON_FLAG_HASH_ID_UINT16: UInt16 = 0x0200
    static let TNS_JSON_FLAG_NUM_FNAMES_UINT16: UInt16 = 0x0400
    static let TNS_JSON_FLAG_FNAMES_SEG_UINT32: UInt16 = 0x0800
    static let TNS_JSON_FLAG_TINY_NODES_STAT = 0x2000
    static let TNS_JSON_FLAG_TREE_SEG_UINT32: UInt16 = 0x1000
    static let TNS_JSON_FLAG_REL_OFFSET_MODE = 0x01
    static let TNS_JSON_FLAG_INLINE_LEAF = 0x02
    static let TNS_JSON_FLAG_LEN_IN_PCODE = 0x04
    static let TNS_JSON_FLAG_NUM_FNAMES_UINT32: UInt16 = 0x08
    static let TNS_JSON_FLAG_IS_SCALAR: UInt16 = 0x10

    // MARK: JSON data types
    static let TNS_JSON_TYPE_NULL: UInt8 = 0x30
    static let TNS_JSON_TYPE_TRUE: UInt8 = 0x31
    static let TNS_JSON_TYPE_FALSE: UInt8 = 0x32
    static let TNS_JSON_TYPE_STRING_LENGTH_UINT8: UInt8 = 0x33
    static let TNS_JSON_TYPE_NUMBER_LENGTH_UINT8: UInt8 = 0x34
    static let TNS_JSON_TYPE_BINARY_DOUBLE: UInt8 = 0x36
    static let TNS_JSON_TYPE_STRING_LENGTH_UINT16: UInt8 = 0x37
    static let TNS_JSON_TYPE_STRING_LENGTH_UINT32: UInt8 = 0x38
    static let TNS_JSON_TYPE_TIMESTAMP: UInt8 = 0x39
    static let TNS_JSON_TYPE_BINARY_LENGTH_UINT16: UInt8 = 0x3a
    static let TNS_JSON_TYPE_BINARY_LENGTH_UINT32: UInt8 = 0x3b
    static let TNS_JSON_TYPE_DATE: UInt8 = 0x3c
    static let TNS_JSON_TYPE_INTERVAL_YM: UInt8 = 0x3d
    static let TNS_JSON_TYPE_INTERVAL_DS: UInt8 = 0x3e
    static let TNS_JSON_TYPE_TIMESTAMP_TZ: UInt8 = 0x7c
    static let TNS_JSON_TYPE_TIMESTAMP7: UInt8 = 0x7d
    static let TNS_JSON_TYPE_BINARY_FLOAT: UInt8 = 0x7f
    static let TNS_JSON_TYPE_OBJECT = 0x84
    static let TNS_JSON_TYPE_ARRAY = 0xc0
    static let TNS_JSON_TYPE_EXTENDED = 0x7b
    static let TNS_JSON_TYPE_VECTOR = 0x01

    // MARK: VECTOR constants
    static let TNS_VECTOR_MAGIC_BYTE = 0xDB
    static let TNS_VECTOR_VERSION = 0
    static let TNS_VECTOR_MAX_LENGTH: UInt32 = 1 * 1024 * 1024

    // MARK: VECTOR flags
    static let TNS_VECTOR_FLAG_NORM: UInt16 = 0x0002
    static let TNS_VECTOR_FLAG_NORM_RESERVED: UInt16 = 0x0010
    static let VECTOR_META_FLAG_FLEXIBLE_DIM: UInt8 = 0x01

    // MARK: VECTOR formats
    static let VECTOR_FORMAT_FLOAT32: UInt8 = 2
    static let VECTOR_FORMAT_FLOAT64: UInt8 = 3
    static let VECTOR_FORMAT_INT8: UInt8 = 4

    // MARK: End-to-End metrics
    static let TNS_END_TO_END_ACTION = 0x0010
    static let TNS_END_TO_END_CLIENT_IDENTIFIER = 0x0001
    static let TNS_END_TO_END_CLIENT_INFO = 0x0100
    static let TNS_END_TO_END_DBOP = 0x0200
    static let TNS_END_TO_END_MODULE = 0x0008

    // MARK: Versions
    static let TNS_VERSION_DESIRED: UInt16 = 319
    static let TNS_VERSION_MINIMUM: UInt16 = 300
    static let TNS_VERSION_MIN_ACCEPTED: UInt16 = 315  // 12.1
    static let TNS_VERSION_MIN_LARGE_SDU: UInt16 = 315
    static let TNS_VERSION_MIN_OOB_CHECK: UInt16 = 318
    static let TNS_VERSION_MIN_END_OF_RESPONSE: UInt16 = 319

    // MARK: Control packet types
    static let TNS_CONTROL_TYPE_INBAND_NOTIFICATION = 8
    static let TNS_CONTROL_TYPE_RESET_OOB = 9

    // MARK: Connect flags
    static let TNS_GSO_DONT_CARE: UInt16 = 0x0001
    static let TNS_GSO_CAN_RECV_ATTENTION: UInt16 = 0x0400
    static let TNS_NSI_DISABLE_NA: UInt8 = 0x04
    static let TNS_NSI_SUPPORT_SECURITY_RENEG: UInt8 = 0x80

    // MARK: Other connection constants
    static let TNS_PROTOCOL_CHARACTERISTICS: UInt16 = 0x4f98
    static let TNS_CHECK_OOB: UInt32 = 0x01

    // MARK: TTC functions
    enum FunctionCode: UInt8 {
        case authPhaseOne = 118
        case authPhaseTwo = 115
        case closeCursors = 105
        case commit = 14
        case execute = 94
        case fetch = 5
        case lobOp = 96
        case logoff = 9
        case ping = 147
        case rollback = 15
        case setEndToEndAttr = 135
        case reexecute = 4
        case reexecuteAndFetch = 78
        case sessionGet = 162
        case sessionRelease = 163
        case setSchema = 152
    }

    // MARK: TTC authentication modes
    static let TNS_AUTH_MODE_LOGON: UInt32 = 0x0000_0001
    static let TNS_AUTH_MODE_CHANGE_PASSWORD: UInt32 = 0x0000_0002
    static let TNS_AUTH_MODE_SYSDBA: UInt32 = 0x0000_0020
    static let TNS_AUTH_MODE_SYSOPER: UInt32 = 0x0000_0040
    static let TNS_AUTH_MODE_PRELIM: UInt32 = 0x0000_0080
    static let TNS_AUTH_MODE_WITH_PASSWORD: UInt32 = 0x0000_0100
    static let TNS_AUTH_MODE_SYSASM: UInt32 = 0x0040_0000
    static let TNS_AUTH_MODE_SYSBKP: UInt32 = 0x0100_0000
    static let TNS_AUTH_MODE_SYSDGD: UInt32 = 0x0200_0000
    static let TNS_AUTH_MODE_SYSKMT: UInt32 = 0x0400_0000
    static let TNS_AUTH_MODE_SYSRAC: UInt32 = 0x0800_0000
    static let TNS_AUTH_MODE_IAM_TOKEN: UInt32 = 0x2000_0000

    // MARK: Character sets and encodings
    static let TNS_CHARSET_AL16UTF8: UInt16 = 208
    static let TNS_CHARSET_UTF8: UInt16 = 873
    static let TNS_CHARSET_UTF16: UInt16 = 2000
    static let TNS_ENCODING_UTF8 = "UTF-8"
    static let TNS_ENCODING_UTF16 = "UTF-16BE"
    static let TNS_ENCODING_MULTI_BYTE = 0x01
    static let TNS_ENCODING_CONV_LENGTH = 0x02

    // MARK: Compile time capability indices
    static let TNS_CCAP_SQL_VERSION = 0
    static let TNS_CCAP_LOGON_TYPES = 4
    static let TNS_CCAP_FEATURE_BACKPORT = 5
    static let TNS_CCAP_FIELD_VERSION = 7
    static let TNS_CCAP_SERVER_DEFINE_CONV = 8
    static let TNS_CCAP_TTC1 = 15
    static let TNS_CCAP_OCI1 = 16
    static let TNS_CCAP_TDS_VERSION = 17
    static let TNS_CCAP_RPC_VERSION = 18
    static let TNS_CCAP_RPC_SIG = 19
    static let TNS_CCAP_DBF_VERSION = 21
    static let TNS_CCAP_LOB = 23
    static let TNS_CCAP_TTC2 = 26
    static let TNS_CCAP_UB2_DTY = 27
    static let TNS_CCAP_OCI2 = 31
    static let TNS_CCAP_CLIENT_FN = 34
    static let TNS_CCAP_TTC3 = 37
    static let TNS_CCAP_TTC4 = 40
    static let TNS_CCAP_LOB2 = 42
    static let TNS_CCAP_TTC5 = 44
    static let TNS_CCAP_MAX = 51

    // MARK: Compile time capability values
    static let TNS_CCAP_SQL_VERSION_MAX: UInt8 = 6
    static let TNS_CCAP_FIELD_VERSION_11_2 = 6
    static let TNS_CCAP_FIELD_VERSION_12_1 = 7
    static let TNS_CCAP_FIELD_VERSION_12_2 = 8
    static let TNS_CCAP_FIELD_VERSION_12_2_EXT1 = 9
    static let TNS_CCAP_FIELD_VERSION_18_1 = 10
    static let TNS_CCAP_FIELD_VERSION_18_1_EXT_1 = 11
    static let TNS_CCAP_FIELD_VERSION_19_1 = 12
    static let TNS_CCAP_FIELD_VERSION_19_1_EXT_1: UInt8 = 13
    static let TNS_CCAP_FIELD_VERSION_20_1 = 14
    static let TNS_CCAP_FIELD_VERSION_20_1_EXT_1 = 15
    static let TNS_CCAP_FIELD_VERSION_21_1 = 16
    static let TNS_CCAP_FIELD_VERSION_23_1 = 17
    static let TNS_CCAP_FIELD_VERSION_23_1_EXT_1 = 18
    static let TNS_CCAP_FIELD_VERSION_23_1_EXT_2 = 19
    static let TNS_CCAP_FIELD_VERSION_23_1_EXT_3 = 20
    static let TNS_CCAP_FIELD_VERSION_23_1_EXT_4 = 21
    static let TNS_CCAP_FIELD_VERSION_23_1_EXT_5 = 22
    static let TNS_CCAP_FIELD_VERSION_23_3_EXT_6 = 23
    static let TNS_CCAP_FIELD_VERSION_23_4 = 24
    static let TNS_CCAP_FIELD_VERSION_MAX: UInt8 = 24
    static let TNS_CCAP_O5LOGON: UInt8 = 8
    static let TNS_CCAP_O5LOGON_NP: UInt8 = 2
    static let TNS_CCAP_O7LOGON: UInt8 = 32
    static let TNS_CCAP_O8LOGON_LONG_IDENTIFIER: UInt8 = 64
    static let TNS_CCAP_O9LOGON_LONG_PASSWORD: UInt8 = 0x80
    static let TNS_CCAP_CTB_IMPLICIT_POOL: UInt8 = 0x08
    static let TNS_CCAP_END_OF_CALL_STATUS: UInt8 = 0x01
    static let TNS_CCAP_IND_RCD: UInt8 = 0x08
    static let TNS_CCAP_FAST_BVEC: UInt8 = 0x20
    static let TNS_CCAP_FAST_SESSION_PROPAGATE: UInt8 = 0x10
    static let TNS_CCAP_APP_CTX_PIGGYBACK: UInt8 = 0x80
    static let TNS_CCAP_TDS_VERSION_MAX: UInt8 = 3
    static let TNS_CCAP_RPC_VERSION_MAX: UInt8 = 7
    static let TNS_CCAP_RPC_SIG_VALUE: UInt8 = 3
    static let TNS_CCAP_DBF_VERSION_MAX: UInt8 = 1
    static let TNS_CCAP_IMPLICIT_RESULTS: UInt8 = 0x10
    static let TNS_CCAP_BIG_CHUNK_CLR: UInt8 = 0x20
    static let TNS_CCAP_KEEP_OUT_ORDER: UInt8 = 0x80
    static let TNS_CCAP_LOB_UB8_SIZE: UInt8 = 0x01
    static let TNS_CCAP_LOB_ENCS: UInt8 = 0x02
    static let TNS_CCAP_LOB_PREFETCH_DATA: UInt8 = 0x04
    static let TNS_CCAP_LOB_TEMP_SIZE: UInt8 = 0x08
    static let TNS_CCAP_LOB_PREFETCH_LENGTH: UInt8 = 0x40
    static let TNS_CCAP_LOB_12C: UInt8 = 0x80
    static let TNS_CCAP_LOB2_QUASI: UInt8 = 0x01
    static let TNS_CCAP_LOB2_2GB_PREFETCH: UInt8 = 0x04
    static let TNS_CCAP_DRCP: UInt8 = 0x10
    static let TNS_CCAP_ZLNP: UInt8 = 0x04
    static let TNS_CCAP_INBAND_NOTIFICATION: UInt8 = 0x04
    static let TNS_CCAP_END_OF_REQUEST: UInt8 = 0x20
    static let TNS_CCAP_CLIENT_FN_MAX: UInt8 = 12
    static let TNS_CCAP_VECTOR_SUPPORT: UInt8 = 0x08

    // MARK: Runtime capability indices
    static let TNS_RCAP_COMPAT = 0
    static let TNS_RCAP_TTC = 6
    static let TNS_RCAP_MAX = 11

    // MARK: Runtime capability values
    static let TNS_RCAP_COMPAT_81: UInt8 = 2
    static let TNS_RCAP_TTC_ZERO_COPY: UInt8 = 0x01
    static let TNS_RCAP_TTC_32K: UInt8 = 0x04

    // MARK: Verifier types
    static let TNS_VERIFIER_TYPE_11G_1: UInt32 = 0xb152
    static let TNS_VERIFIER_TYPE_11G_2: UInt32 = 0x1b25
    static let TNS_VERIFIER_TYPE_12C: UInt32 = 0x4815

    // MARK: Accept flags
    static let TNS_ACCEPT_FLAG_FAST_AUTH: UInt32 = 0x1000_0000
    static let TNS_ACCEPT_FLAG_HAS_END_OF_REQUEST: UInt32 = 0x0200_0000

    // MARK: Other constants
    static let TNS_MAX_SHORT_LENGTH = 252
    @usableFromInline
    static let TNS_ESCAPE_CHAR: UInt8 = 253
    @usableFromInline
    static let TNS_LONG_LENGTH_INDICATOR: UInt8 = 254
    @usableFromInline
    static let TNS_NULL_LENGTH_INDICATOR: UInt8 = 255
    static let TNS_MAX_ROWID_LENGTH = 18
    static let TNS_DURATION_MID: UInt32 = 0x8000_0000
    static let TNS_DURATION_OFFSET: UInt8 = 60
    static let TNS_DURATION_SESSION: Int64 = 10
    @usableFromInline
    static let TNS_MIN_LONG_LENGTH = 0x8000
    static let TNS_MAX_LONG_LENGTH: UInt32 = 0x7fff_ffff
    static let TNS_SDU: UInt16 = 8192
    static let TNS_TDU: UInt16 = 65535
    static let TNS_MAX_CURSORS_TO_CLOSE = 500
    static let TNS_TXN_IN_PROGRESS = 0x0000_0002
    static let TNS_MAX_CONNECT_DATA = 230
    static let TNS_CHUNK_SIZE = 32767
    static let TNS_MAX_UROWID_LENGTH: UInt32 = 5267
    static let TNS_SERVER_CONVERTS_CHARS: UInt8 = 0x01
    static let TNS_HAS_REGION_ID: UInt8 = 0x80

    // MARK: Base 64 encoding alphabet
    static let TNS_BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    static let TNS_BASE64_ALPHABET_ARRAY = Array(TNS_BASE64_ALPHABET.utf8)
    static let TNS_EXTENT_OID = 0x0000_0000_0000_0000_0000_0000_0001_0001

    // MARK: Timezone offsets
    static let TZ_HOUR_OFFSET: UInt8 = 20
    static let TZ_MINUTE_OFFSET: UInt8 = 60

    // MARK: DRCP release mode
    static let DRCP_DEAUTHENTICATE: UInt32 = 0x0000_0002

}

extension Constants {
    // MARK: Mandated DB API constants
    static let apilevel = "2.0"
    static let threadsafety = 2
    static let paramstyle = "named"

    // MARK: Pool "get" modes
    static let POOL_GETMODE_WAIT = 0
    static let POOL_GETMODE_NOWAIT = 1
    static let POOL_GETMODE_FORCEGET = 2
    static let POOL_GETMODE_TIMEDWAIT = 3

    // MARK: AQ delivery modes
    static let MSG_BUFFERED = 2
    static let MSG_PERSISTENT = 1
    static let MSG_PERSISTENT_OR_BUFFERED = 3

    // MARK: AQ deque modes
    static let DEQ_BROWSE = 1
    static let DEQ_LOCKED = 2
    static let DEQ_REMOVE = 3
    static let DEQ_REMOVE_NODATA = 4

    // MARK: AQ dequeue navigation modes
    static let DEQ_FIRST_MSG = 1
    static let DEQ_NEXT_MSG = 3
    static let DEQ_NEXT_TRANSACTION = 2

    // MARK: AQ dequeue visibility modes
    static let DEQ_IMMEDIATE = 1
    static let DEQ_ON_COMMIT = 2

    // MARK: AQ dequeue wait modes
    static let DEQ_NO_WAIT = 0
    static let DEQ_WAIT_FOREVER = pow(2, 32) - 1

    // MARK: AQ enqueue visibility modes
    static let ENQ_IMMEDIATE = 1
    static let ENQ_ON_COMMIT = 2

    // MARK: AQ message states
    static let MSG_EXPIRED = 3
    static let MSG_PROCESSED = 2
    static let MSG_READY = 0
    static let MSG_WAITING = 1

    // MARK: AQ other constants
    static let MSG_NO_DELAY = 0
    static let MSG_NO_EXPIRATION = -1

    // MARK: Shutdown modes
    static let DBSHUTDOWN_ABORT = 4
    static let DBSHUTDOWN_FINAL = 5
    static let DBSHUTDOWN_IMMEDIATE = 3
    static let DBSHUTDOWN_TRANSACTIONAL = 1
    static let DBSHUTDOWN_TRANSACTIONAL_LOCAL = 2

    // MARK: Subscription grouping classes
    static let SUBSCR_GROUPING_CLASS_NONE = 0
    static let SUBSCR_GROUPING_CLASS_TIME = 1

    // MARK: Subscription grouping types
    static let SUBSCR_GROUPING_TYPE_SUMMARY = 1
    static let SUBSCR_GROUPING_TYPE_LAST = 2

    // MARK: Subscription namespaces
    static let SUBSCR_NAMESPACE_AQ = 1
    static let SUBSCR_NAMESPACE_DBCHANGE = 2

    // MARK: Subscription protocols
    static let SUBSCR_PROTO_HTTP = 3
    static let SUBSCR_PROTO_MAIL = 1
    static let SUBSCR_PROTO_CALLBACK = 0
    static let SUBSCR_PROTO_SERVER = 2

    // MARK: Subscription quality of service
    static let SUBSCR_QOS_BEST_EFFORT = 0x10
    static let SUBSCR_QOS_DEFAULT = 0
    static let SUBSCR_QOS_DEREG_NFY = 0x02
    static let SUBSCR_QOS_QUERY = 0x08
    static let SUBSCR_QOS_RELIABLE = 0x01
    static let SUBSCR_QOS_ROWIDS = 0x04

    // MARK: Event types
    static let EVENT_AQ = 100
    static let EVENT_DEREG = 5
    static let EVENT_NONE = 0
    static let EVENT_OBJCHANGE = 6
    static let EVENT_QUERYCHANGE = 7
    static let EVENT_SHUTDOWN = 2
    static let EVENT_SHUTDOWN_ANY = 3
    static let EVENT_STARTUP = 1

    // MARK: Operation codes
    static let OPCODE_ALLOPS = 0
    static let OPCODE_ALLROWS = 0x01
    static let OPCODE_ALTER = 0x10
    static let OPCODE_DELETE = 0x08
    static let OPCODE_DROP = 0x20
    static let OPCODE_INSERT = 0x02
    static let OPCODE_UPDATE = 0x04

    // MARK: Flags for tpc_begin()
    static let TPC_BEGIN_JOIN = 0x0000_0002
    static let TPC_BEGIN_NEW = 0x0000_0001
    static let TPC_BEGIN_PROMOTE = 0x0000_0008
    static let TPC_BEGIN_RESUME = 0x0000_0004

    // MARK: Flags for tpc_end()
    static let TPC_END_NORMAL = 0
    static let TPC_END_SUSPEND = 0x0010_0000

    // MARK: Basic configuration constants
    static let DRIVER_NAME = "oracle-nio"
    static let VERSION_TUPLE = (major: 1, minor: 0, patch: 0)
    static let VERSION_CODE =
        VERSION_TUPLE.major << 24 | VERSION_TUPLE.minor << 20 | VERSION_TUPLE.patch << 12
    static let VERSION = "\(VERSION_TUPLE.major).\(VERSION_TUPLE.minor).\(VERSION_TUPLE.patch)"
    static let ENCODING = "UTF-8"

}
