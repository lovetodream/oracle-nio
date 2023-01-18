//
//  Constants.swift
//  OracleNIO
//
//  Created by Timo Zacherl on 05.01.23.
//
//  Defining constants used by the thin implementation classes.
//

import Foundation

enum Constants {
    // MARK: TNS Packet Types
    enum PacketType: UInt8 {
        case connect = 1
        case accept = 2
        case refuse = 4
        case data = 6
        case resend = 11
        case marker = 12
        case control = 14
        case redirect = 5
    }

    // MARK: Packet flags
    static let TNS_PACKET_FLAG_TLS_RENEG = 0x08

    // MARK: Data flags
    static let TNS_DATA_FLAGS_EOF = 0x0040

    // MARK: Marker types
    static let TNS_MARKER_TYPE_BREAK = 1
    static let TNS_MARKER_TYPE_RESET = 2
    static let TNS_MARKER_TYPE_INTERRUPT = 3

    // MARK: Charset forms
    static let TNS_CS_IMPLICIT = 1
    static let TNS_CS_NCHAR = 2

    // MARK: Data types
    static let TNS_DATA_TYPE_VARCHAR = 1
    static let TNS_DATA_TYPE_NUMBER = 2
    static let TNS_DATA_TYPE_BINARY_INTEGER = 3
    static let TNS_DATA_TYPE_FLOAT = 4
    static let TNS_DATA_TYPE_STR = 5
    static let TNS_DATA_TYPE_VNU = 6
    static let TNS_DATA_TYPE_PDN = 7
    static let TNS_DATA_TYPE_LONG = 8
    static let TNS_DATA_TYPE_VCS = 9
    static let TNS_DATA_TYPE_TIDDEF = 10
    static let TNS_DATA_TYPE_ROWID = 11
    static let TNS_DATA_TYPE_DATE = 12
    static let TNS_DATA_TYPE_VBI = 15
    static let TNS_DATA_TYPE_RAW = 23
    static let TNS_DATA_TYPE_LONG_RAW = 24
    static let TNS_DATA_TYPE_UB2 = 25
    static let TNS_DATA_TYPE_UB4 = 26
    static let TNS_DATA_TYPE_SB1 = 27
    static let TNS_DATA_TYPE_SB2 = 28
    static let TNS_DATA_TYPE_SB4 = 29
    static let TNS_DATA_TYPE_SWORD = 30
    static let TNS_DATA_TYPE_UWORD = 31
    static let TNS_DATA_TYPE_PTRB = 32
    static let TNS_DATA_TYPE_PTRW = 33
    static let TNS_DATA_TYPE_OER8 = 34 + 256
    static let TNS_DATA_TYPE_FUN = 35 + 256
    static let TNS_DATA_TYPE_AUA = 36 + 256
    static let TNS_DATA_TYPE_RXH7 = 37 + 256
    static let TNS_DATA_TYPE_NA6 = 38 + 256
    static let TNS_DATA_TYPE_OAC = 39
    static let TNS_DATA_TYPE_AMS = 40
    static let TNS_DATA_TYPE_BRN = 41
    static let TNS_DATA_TYPE_BRP = 42 + 256
    static let TNS_DATA_TYPE_BRV = 43 + 256
    static let TNS_DATA_TYPE_KVA = 44 + 256
    static let TNS_DATA_TYPE_CLS = 45 + 256
    static let TNS_DATA_TYPE_CUI = 46 + 256
    static let TNS_DATA_TYPE_DFN = 47 + 256
    static let TNS_DATA_TYPE_DQR = 48 + 256
    static let TNS_DATA_TYPE_DSC = 49 + 256
    static let TNS_DATA_TYPE_EXE = 50 + 256
    static let TNS_DATA_TYPE_FCH = 51 + 256
    static let TNS_DATA_TYPE_GBV = 52 + 256
    static let TNS_DATA_TYPE_GEM = 53 + 256
    static let TNS_DATA_TYPE_GIV = 54 + 256
    static let TNS_DATA_TYPE_OKG = 55 + 256
    static let TNS_DATA_TYPE_HMI = 56 + 256
    static let TNS_DATA_TYPE_INO = 57 + 256
    static let TNS_DATA_TYPE_LNF = 59 + 256
    static let TNS_DATA_TYPE_ONT = 60 + 256
    static let TNS_DATA_TYPE_OPE = 61 + 256
    static let TNS_DATA_TYPE_OSQ = 62 + 256
    static let TNS_DATA_TYPE_SFE = 63 + 256
    static let TNS_DATA_TYPE_SPF = 64 + 256
    static let TNS_DATA_TYPE_VSN = 65 + 256
    static let TNS_DATA_TYPE_UD7 = 66 + 256
    static let TNS_DATA_TYPE_DSA = 67 + 256
    static let TNS_DATA_TYPE_UIN = 68
    static let TNS_DATA_TYPE_PIN = 71 + 256
    static let TNS_DATA_TYPE_PFN = 72 + 256
    static let TNS_DATA_TYPE_PPT = 73 + 256
    static let TNS_DATA_TYPE_STO = 75 + 256
    static let TNS_DATA_TYPE_ARC = 77 + 256
    static let TNS_DATA_TYPE_MRS = 78 + 256
    static let TNS_DATA_TYPE_MRT = 79 + 256
    static let TNS_DATA_TYPE_MRG = 80 + 256
    static let TNS_DATA_TYPE_MRR = 81 + 256
    static let TNS_DATA_TYPE_MRC = 82 + 256
    static let TNS_DATA_TYPE_VER = 83 + 256
    static let TNS_DATA_TYPE_LON2 = 84 + 256
    static let TNS_DATA_TYPE_INO2 = 85 + 256
    static let TNS_DATA_TYPE_ALL = 86 + 256
    static let TNS_DATA_TYPE_UDB = 87 + 256
    static let TNS_DATA_TYPE_AQI = 88 + 256
    static let TNS_DATA_TYPE_ULB = 89 + 256
    static let TNS_DATA_TYPE_ULD = 90 + 256
    static let TNS_DATA_TYPE_SLS = 91
    static let TNS_DATA_TYPE_SID = 92 + 256
    static let TNS_DATA_TYPE_NA7 = 93 + 256
    static let TNS_DATA_TYPE_LVC = 94
    static let TNS_DATA_TYPE_LVB = 95
    static let TNS_DATA_TYPE_CHAR = 96
    static let TNS_DATA_TYPE_AVC = 97
    static let TNS_DATA_TYPE_AL7 = 98 + 256
    static let TNS_DATA_TYPE_K2RPC = 99 + 256
    static let TNS_DATA_TYPE_BINARY_FLOAT = 100
    static let TNS_DATA_TYPE_BINARY_DOUBLE = 101
    static let TNS_DATA_TYPE_CURSOR = 102
    static let TNS_DATA_TYPE_RDD = 104
    static let TNS_DATA_TYPE_XDP = 103 + 256
    static let TNS_DATA_TYPE_OSL = 106
    static let TNS_DATA_TYPE_OKO8 = 107 + 256
    static let TNS_DATA_TYPE_EXT_NAMED = 108
    static let TNS_DATA_TYPE_INT_NAMED = 109
    static let TNS_DATA_TYPE_EXT_REF = 110
    static let TNS_DATA_TYPE_INT_REF = 111
    static let TNS_DATA_TYPE_CLOB = 112
    static let TNS_DATA_TYPE_BLOB = 113
    static let TNS_DATA_TYPE_BFILE = 114
    static let TNS_DATA_TYPE_CFILE = 115
    static let TNS_DATA_TYPE_RSET = 116
    static let TNS_DATA_TYPE_CWD = 117
    static let TNS_DATA_TYPE_JSON = 119
    static let TNS_DATA_TYPE_NEW_OAC = 120
    static let TNS_DATA_TYPE_UD12 = 124 + 256
    static let TNS_DATA_TYPE_AL8 = 125 + 256
    static let TNS_DATA_TYPE_LFOP = 126 + 256
    static let TNS_DATA_TYPE_FCRT = 127 + 256
    static let TNS_DATA_TYPE_DNY = 128 + 256
    static let TNS_DATA_TYPE_OPR = 129 + 256
    static let TNS_DATA_TYPE_PLS = 130 + 256
    static let TNS_DATA_TYPE_XID = 131 + 256
    static let TNS_DATA_TYPE_TXN = 132 + 256
    static let TNS_DATA_TYPE_DCB = 133 + 256
    static let TNS_DATA_TYPE_CCA = 134 + 256
    static let TNS_DATA_TYPE_WRN = 135 + 256
    static let TNS_DATA_TYPE_TLH = 137 + 256
    static let TNS_DATA_TYPE_TOH = 138 + 256
    static let TNS_DATA_TYPE_FOI = 139 + 256
    static let TNS_DATA_TYPE_SID2 = 140 + 256
    static let TNS_DATA_TYPE_TCH = 141 + 256
    static let TNS_DATA_TYPE_PII = 142 + 256
    static let TNS_DATA_TYPE_PFI = 143 + 256
    static let TNS_DATA_TYPE_PPU = 144 + 256
    static let TNS_DATA_TYPE_PTE = 145 + 256
    static let TNS_DATA_TYPE_CLV = 146
    static let TNS_DATA_TYPE_RXH8 = 148 + 256
    static let TNS_DATA_TYPE_N12 = 149 + 256
    static let TNS_DATA_TYPE_AUTH = 150 + 256
    static let TNS_DATA_TYPE_KVAL = 151 + 256
    static let TNS_DATA_TYPE_DTR = 152
    static let TNS_DATA_TYPE_DUN = 153
    static let TNS_DATA_TYPE_DOP = 154
    static let TNS_DATA_TYPE_VST = 155
    static let TNS_DATA_TYPE_ODT = 156
    static let TNS_DATA_TYPE_FGI = 157 + 256
    static let TNS_DATA_TYPE_DSY = 158 + 256
    static let TNS_DATA_TYPE_DSYR8 = 159 + 256
    static let TNS_DATA_TYPE_DSYH8 = 160 + 256
    static let TNS_DATA_TYPE_DSYL = 161 + 256
    static let TNS_DATA_TYPE_DSYT8 = 162 + 256
    static let TNS_DATA_TYPE_DSYV8 = 163 + 256
    static let TNS_DATA_TYPE_DSYP = 164 + 256
    static let TNS_DATA_TYPE_DSYF = 165 + 256
    static let TNS_DATA_TYPE_DSYK = 166 + 256
    static let TNS_DATA_TYPE_DSYY = 167 + 256
    static let TNS_DATA_TYPE_DSYQ = 168 + 256
    static let TNS_DATA_TYPE_DSYC = 169 + 256
    static let TNS_DATA_TYPE_DSYA = 170 + 256
    static let TNS_DATA_TYPE_OT8 = 171 + 256
    static let TNS_DATA_TYPE_DOL = 172
    static let TNS_DATA_TYPE_DSYTY = 173 + 256
    static let TNS_DATA_TYPE_AQE = 174 + 256
    static let TNS_DATA_TYPE_KV = 175 + 256
    static let TNS_DATA_TYPE_AQD = 176 + 256
    static let TNS_DATA_TYPE_AQ8 = 177 + 256
    static let TNS_DATA_TYPE_TIME = 178
    static let TNS_DATA_TYPE_TIME_TZ = 179
    static let TNS_DATA_TYPE_TIMESTAMP = 180
    static let TNS_DATA_TYPE_TIMESTAMP_TZ = 181
    static let TNS_DATA_TYPE_INTERVAL_YM = 182
    static let TNS_DATA_TYPE_INTERVAL_DS = 183
    static let TNS_DATA_TYPE_EDATE = 184
    static let TNS_DATA_TYPE_ETIME = 185
    static let TNS_DATA_TYPE_ETTZ = 186
    static let TNS_DATA_TYPE_ESTAMP = 187
    static let TNS_DATA_TYPE_ESTZ = 188
    static let TNS_DATA_TYPE_EIYM = 189
    static let TNS_DATA_TYPE_EIDS = 190
    static let TNS_DATA_TYPE_RFS = 193 + 256
    static let TNS_DATA_TYPE_RXH10 = 194 + 256
    static let TNS_DATA_TYPE_DCLOB = 195
    static let TNS_DATA_TYPE_DBLOB = 196
    static let TNS_DATA_TYPE_DBFILE = 197
    static let TNS_DATA_TYPE_DJSON = 198
    static let TNS_DATA_TYPE_KPN = 198 + 256
    static let TNS_DATA_TYPE_KPDNR = 199 + 256
    static let TNS_DATA_TYPE_DSYD = 200 + 256
    static let TNS_DATA_TYPE_DSYS = 201 + 256
    static let TNS_DATA_TYPE_DSYR = 202 + 256
    static let TNS_DATA_TYPE_DSYH = 203 + 256
    static let TNS_DATA_TYPE_DSYT = 204 + 256
    static let TNS_DATA_TYPE_DSYV = 205 + 256
    static let TNS_DATA_TYPE_AQM = 206 + 256
    static let TNS_DATA_TYPE_OER11 = 207 + 256
    static let TNS_DATA_TYPE_UROWID = 208
    static let TNS_DATA_TYPE_AQL = 210 + 256
    static let TNS_DATA_TYPE_OTC = 211 + 256
    static let TNS_DATA_TYPE_KFNO = 212 + 256
    static let TNS_DATA_TYPE_KFNP = 213 + 256
    static let TNS_DATA_TYPE_KGT8 = 214 + 256
    static let TNS_DATA_TYPE_RASB4 = 215 + 256
    static let TNS_DATA_TYPE_RAUB2 = 216 + 256
    static let TNS_DATA_TYPE_RAUB1 = 217 + 256
    static let TNS_DATA_TYPE_RATXT = 218 + 256
    static let TNS_DATA_TYPE_RSSB4 = 219 + 256
    static let TNS_DATA_TYPE_RSUB2 = 220 + 256
    static let TNS_DATA_TYPE_RSUB1 = 221 + 256
    static let TNS_DATA_TYPE_RSTXT = 222 + 256
    static let TNS_DATA_TYPE_RIDL = 223 + 256
    static let TNS_DATA_TYPE_GLRDD = 224 + 256
    static let TNS_DATA_TYPE_GLRDG = 225 + 256
    static let TNS_DATA_TYPE_GLRDC = 226 + 256
    static let TNS_DATA_TYPE_OKO = 227 + 256
    static let TNS_DATA_TYPE_DPP = 228 + 256
    static let TNS_DATA_TYPE_DPLS = 229 + 256
    static let TNS_DATA_TYPE_DPMOP = 230 + 256
    static let TNS_DATA_TYPE_TIMESTAMP_LTZ = 231
    static let TNS_DATA_TYPE_ESITZ = 232
    static let TNS_DATA_TYPE_UB8 = 233
    static let TNS_DATA_TYPE_STAT = 234 + 256
    static let TNS_DATA_TYPE_RFX = 235 + 256
    static let TNS_DATA_TYPE_FAL = 236 + 256
    static let TNS_DATA_TYPE_CKV = 237 + 256
    static let TNS_DATA_TYPE_DRCX = 238 + 256
    static let TNS_DATA_TYPE_KGH = 239 + 256
    static let TNS_DATA_TYPE_AQO = 240 + 256
    static let TNS_DATA_TYPE_PNTY = 241
    static let TNS_DATA_TYPE_OKGT = 242 + 256
    static let TNS_DATA_TYPE_KPFC = 243 + 256
    static let TNS_DATA_TYPE_FE2 = 244 + 256
    static let TNS_DATA_TYPE_SPFP = 245 + 256
    static let TNS_DATA_TYPE_DPULS = 246 + 256
    static let TNS_DATA_TYPE_BOOLEAN = 252
    static let TNS_DATA_TYPE_AQA = 253 + 256
    static let TNS_DATA_TYPE_KPBF = 254 + 256
    static let TNS_DATA_TYPE_TSM = 513
    static let TNS_DATA_TYPE_MSS = 514
    static let TNS_DATA_TYPE_KPC = 516
    static let TNS_DATA_TYPE_CRS = 517
    static let TNS_DATA_TYPE_KKS = 518
    static let TNS_DATA_TYPE_KSP = 519
    static let TNS_DATA_TYPE_KSPTOP = 520
    static let TNS_DATA_TYPE_KSPVAL = 521
    static let TNS_DATA_TYPE_PSS = 522
    static let TNS_DATA_TYPE_NLS = 523
    static let TNS_DATA_TYPE_ALS = 524
    static let TNS_DATA_TYPE_KSDEVTVAL = 525
    static let TNS_DATA_TYPE_KSDEVTTOP = 526
    static let TNS_DATA_TYPE_KPSPP = 527
    static let TNS_DATA_TYPE_KOL = 528
    static let TNS_DATA_TYPE_LST = 529
    static let TNS_DATA_TYPE_ACX = 530
    static let TNS_DATA_TYPE_SCS = 531
    static let TNS_DATA_TYPE_RXH = 532
    static let TNS_DATA_TYPE_KPDNS = 533
    static let TNS_DATA_TYPE_KPDCN = 534
    static let TNS_DATA_TYPE_KPNNS = 535
    static let TNS_DATA_TYPE_KPNCN = 536
    static let TNS_DATA_TYPE_KPS = 537
    static let TNS_DATA_TYPE_APINF = 538
    static let TNS_DATA_TYPE_TEN = 539
    static let TNS_DATA_TYPE_XSSCS = 540
    static let TNS_DATA_TYPE_XSSSO = 541
    static let TNS_DATA_TYPE_XSSAO = 542
    static let TNS_DATA_TYPE_KSRPC = 543
    static let TNS_DATA_TYPE_KVL = 560
    static let TNS_DATA_TYPE_SESSGET = 563
    static let TNS_DATA_TYPE_SESSREL = 564
    static let TNS_DATA_TYPE_XSSDEF = 565
    static let TNS_DATA_TYPE_PDQCINV = 572
    static let TNS_DATA_TYPE_PDQIDC = 573
    static let TNS_DATA_TYPE_KPDQCSTA = 574
    static let TNS_DATA_TYPE_KPRS = 575
    static let TNS_DATA_TYPE_KPDQIDC = 576
    static let TNS_DATA_TYPE_RTSTRM = 578
    static let TNS_DATA_TYPE_SESSRET = 579
    static let TNS_DATA_TYPE_SCN6 = 580
    static let TNS_DATA_TYPE_KECPA = 581
    static let TNS_DATA_TYPE_KECPP = 582
    static let TNS_DATA_TYPE_SXA = 583
    static let TNS_DATA_TYPE_KVARR = 584
    static let TNS_DATA_TYPE_KPNGN = 585
    static let TNS_DATA_TYPE_XSNSOP = 590
    static let TNS_DATA_TYPE_XSATTR = 591
    static let TNS_DATA_TYPE_XSNS = 592
    static let TNS_DATA_TYPE_TXT = 593
    static let TNS_DATA_TYPE_XSSESSNS = 594
    static let TNS_DATA_TYPE_XSATTOP = 595
    static let TNS_DATA_TYPE_XSCREOP = 596
    static let TNS_DATA_TYPE_XSDETOP = 597
    static let TNS_DATA_TYPE_XSDESOP = 598
    static let TNS_DATA_TYPE_XSSETSP = 599
    static let TNS_DATA_TYPE_XSSIDP = 600
    static let TNS_DATA_TYPE_XSPRIN = 601
    static let TNS_DATA_TYPE_XSKVL = 602
    static let TNS_DATA_TYPE_XSSSDEF2 = 603
    static let TNS_DATA_TYPE_XSNSOP2 = 604
    static let TNS_DATA_TYPE_XSNS2 = 605
    static let TNS_DATA_TYPE_IMPLRES = 611
    static let TNS_DATA_TYPE_OER = 612
    static let TNS_DATA_TYPE_UB1ARRAY = 613
    static let TNS_DATA_TYPE_SESSSTATE = 614
    static let TNS_DATA_TYPE_AC_REPLAY = 615
    static let TNS_DATA_TYPE_AC_CONT = 616
    static let TNS_DATA_TYPE_KPDNREQ = 622
    static let TNS_DATA_TYPE_KPDNRNF = 623
    static let TNS_DATA_TYPE_KPNGNC = 624
    static let TNS_DATA_TYPE_KPNRI = 625
    static let TNS_DATA_TYPE_AQENQ = 626
    static let TNS_DATA_TYPE_AQDEQ = 627
    static let TNS_DATA_TYPE_AQJMS = 628
    static let TNS_DATA_TYPE_KPDNRPAY = 629
    static let TNS_DATA_TYPE_KPDNRACK = 630
    static let TNS_DATA_TYPE_KPDNRMP = 631
    static let TNS_DATA_TYPE_KPDNRDQ = 632
    static let TNS_DATA_TYPE_CHUNKINFO = 636
    static let TNS_DATA_TYPE_SCN = 637
    static let TNS_DATA_TYPE_SCN8 = 638
    static let TNS_DATA_TYPE_UDS = 639
    static let TNS_DATA_TYPE_TNP = 640

    // MARK: Data type representations
    static let TNS_TYPE_REP_NATIVE = 0
    static let TNS_TYPE_REP_UNIVERSAL = 1
    static let TNS_TYPE_REP_ORACLE = 10

    // MARK: Errors
    static let TNS_ERR_VAR_NOT_IN_SELECT_LIST = 1007
    static let TNS_ERR_INBAND_MESSAGE = 12573
    static let TNS_ERR_INVALID_SERVICE_NAME = 12514
    static let TNS_ERR_INVALID_SID = 12505
    static let TNS_ERR_NO_DATA_FOUND = 1403
    static let TNS_ERR_SESSION_SHUTDOWN = 12572
    static let TNS_ERR_ARRAY_DML_ERRORS = 24381

    // MARK: Message types
    static let TNS_MSG_TYPE_PROTOCOL = 1
    static let TNS_MSG_TYPE_DATA_TYPES = 2
    static let TNS_MSG_TYPE_FUNCTION = 3
    static let TNS_MSG_TYPE_ERROR = 4
    static let TNS_MSG_TYPE_ROW_HEADER = 6
    static let TNS_MSG_TYPE_ROW_DATA = 7
    static let TNS_MSG_TYPE_PARAMETER = 8
    static let TNS_MSG_TYPE_STATUS = 9
    static let TNS_MSG_TYPE_IO_VECTOR = 11
    static let TNS_MSG_TYPE_LOB_DATA = 14
    static let TNS_MSG_TYPE_WARNING = 15
    static let TNS_MSG_TYPE_DESCRIBE_INFO = 16
    static let TNS_MSG_TYPE_PIGGYBACK = 17
    static let TNS_MSG_TYPE_FLUSH_OUT_BINDS = 19
    static let TNS_MSG_TYPE_BIT_VECTOR = 21
    static let TNS_MSG_TYPE_SERVER_SIDE_PIGGYBACK = 23
    static let TNS_MSG_TYPE_ONEWAY_FN = 26
    static let TNS_MSG_TYPE_IMPLICIT_RESULTSET = 27

    // MARK: Parameter keyword numbers
    static let TNS_KEYWORD_NUM_CURRENT_SCHEMA = 168
    static let TNS_KEYWORD_NUM_EDITION = 172

    // MARK: Bind flags
    static let TNS_BIND_USE_INDICATORS = 0x0001
    static let TNS_BIND_ARRAY = 0x0040

    // MARK: Bind directions
    static let TNS_BIND_DIR_OUTPUT = 16
    static let TNS_BIND_DIR_INPUT = 32
    static let TNS_BIND_DIR_INPUT_OUTPUT = 48

    // MARK: Database object image flags
    static let TNS_OBJ_IS_VERSION_81 = 0x80
    static let TNS_OBJ_IS_DEGENERATE = 0x10
    static let TNS_OBJ_IS_COLLECTION = 0x08
    static let TNS_OBJ_NO_PREFIX_SEG = 0x04
    static let TNS_OBJ_IMAGE_VERSION = 1

    // MARK: Database object flags
    static let TNS_OBJ_MAX_SHORT_LENGTH = 245
    static let TNS_OBJ_ATOMIC_NULL = 253
    static let TNS_OBJ_NON_NULL_OID = 0x02
    static let TNS_OBJ_HAS_EXTENT_OID = 0x08
    static let TNS_OBJ_TOP_LEVEL = 0x01
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
    static let TNS_XML_TYPE_LOB = 0x0001
    static let TNS_XML_TYPE_STRING = 0x0004
    static let TNS_XML_TYPE_FLAG_SKIP_NEXT_4 = 0x100000

    // MARK: Execute options
    static let TNS_EXEC_OPTION_PARSE = 0x01
    static let TNS_EXEC_OPTION_BIND = 0x08
    static let TNS_EXEC_OPTION_letINE = 0x10
    static let TNS_EXEC_OPTION_EXECUTE = 0x20
    static let TNS_EXEC_OPTION_FETCH = 0x40
    static let TNS_EXEC_OPTION_COMMIT = 0x100
    static let TNS_EXEC_OPTION_COMMIT_REEXECUTE = 0x1
    static let TNS_EXEC_OPTION_PLSQL_BIND = 0x400
    static let TNS_EXEC_OPTION_DML_ROWCOUNTS = 0x4000
    static let TNS_EXEC_OPTION_NOT_PLSQL = 0x8000
    static let TNS_EXEC_OPTION_IMPLICIT_RESULTSET = 0x8000
    static let TNS_EXEC_OPTION_DESCRIBE = 0x20000
    static let TNS_EXEC_OPTION_NO_COMPRESSED_FETCH = 0x40000
    static let TNS_EXEC_OPTION_BATCH_ERRORS = 0x80000

    // MARK: Server side piggyback op codes
    static let TNS_SERVER_PIGGYBACK_QUERY_CACHE_INVALIDATION = 1
    static let TNS_SERVER_PIGGYBACK_OS_PID_MTS = 2
    static let TNS_SERVER_PIGGYBACK_TRACE_EVENT = 3
    static let TNS_SERVER_PIGGYBACK_SESS_RET = 4
    static let TNS_SERVER_PIGGYBACK_SYNC = 5
    static let TNS_SERVER_PIGGYBACK_LTXID = 7
    static let TNS_SERVER_PIGGYBACK_AC_REPLAY_CONTEXT = 8
    static let TNS_SERVER_PIGGYBACK_EXT_SYNC = 9

    // MARK: Session return constants
    static let TNS_SESSGET_SESSION_CHANGED = 4

    // MARK: LOB operations
    static let TNS_LOB_OP_GET_LENGTH = 0x0001
    static let TNS_LOB_OP_READ = 0x0002
    static let TNS_LOB_OP_TRIM = 0x0020
    static let TNS_LOB_OP_WRITE = 0x0040
    static let TNS_LOB_OP_GET_CHUNK_SIZE = 0x4000
    static let TNS_LOB_OP_CREATE_TEMP = 0x0110
    static let TNS_LOB_OP_FREE_TEMP = 0x0111
    static let TNS_LOB_OP_OPEN = 0x8000
    static let TNS_LOB_OP_CLOSE = 0x10000
    static let TNS_LOB_OP_IS_OPEN = 0x11000
    static let TNS_LOB_OP_ARRAY = 0x80000

    // MARK: LOB locator constants
    static let TNS_LOB_LOCATOR_OFFSET_FLAG_3 = 6
    static let TNS_LOB_LOCATOR_VAR_LENGTH_CHARSET = 0x80

    // MARK: Temporary and Abstract LOB constants
    static let TNS_LOB_ABSTRACT_POS = 4
    static let TNS_LOB_TEMP_POS = 7
    static let TNS_LOB_TEMP_VALUE = 0x01
    static let TNS_LOB_ABSTRACT_VALUE = 0x40

    // MARK: Other LOB constants
    static let TNS_LOB_OPEN_READ_WRITE = 2

    // MARK: End-to-End metrics
    static let TNS_END_TO_END_ACTION = 0x0010
    static let TNS_END_TO_END_CLIENT_IDENTIFIER = 0x0001
    static let TNS_END_TO_END_CLIENT_INFO = 0x0100
    static let TNS_END_TO_END_DBOP = 0x0200
    static let TNS_END_TO_END_MODULE = 0x0008

    // MARK: Versions
    static let TNS_VERSION_DESIRED: UInt16 = 318
    static let TNS_VERSION_MINIMUM: UInt16 = 300
    static let TNS_VERSION_MIN_ACCEPTED = 315      // 12.1
    static let TNS_VERSION_MIN_LARGE_SDU = 315
    static let TNS_VERSION_MIN_OOB_CHECK = 318

    // MARK: Control packet types
    static let TNS_CONTROL_TYPE_INBAND_NOTIFICATION = 8
    static let TNS_CONTROL_TYPE_RESET_OOB = 9

    // MARK: Other connection constants
    static let TNS_BASE_SERVICE_OPTIONS: UInt16 = 0x801
    static let TNS_PROTOCOL_CHARACTERISTICS: UInt16 = 0x4f98
    static let TNS_CONNECT_FLAGS: UInt16 = 0x8080
    static let TNS_CAN_RECV_ATTENTION: UInt16 = 0x0400
    static let TNS_CHECK_OOB: UInt32 = 0x01

    // MARK: TTC functions
    static let TNS_FUNC_AUTH_PHASE_ONE = 118
    static let TNS_FUNC_AUTH_PHASE_TWO = 115
    static let TNS_FUNC_CLOSE_CURSORS = 105
    static let TNS_FUNC_COMMIT = 14
    static let TNS_FUNC_EXECUTE = 94
    static let TNS_FUNC_FETCH = 5
    static let TNS_FUNC_LOB_OP = 96
    static let TNS_FUNC_LOGOFF = 9
    static let TNS_FUNC_PING = 147
    static let TNS_FUNC_ROLLBACK = 15
    static let TNS_FUNC_SET_END_TO_END_ATTR = 135
    static let TNS_FUNC_REEXECUTE = 4
    static let TNS_FUNC_REEXECUTE_AND_FETCH = 78
    static let TNS_FUNC_SESSION_GET = 162
    static let TNS_FUNC_SESSION_RELEASE = 163
    static let TNS_FUNC_SET_SCHEMA = 152

    // MARK: TTC authentication modes
    static let TNS_AUTH_MODE_LOGON = 0x00000001
    static let TNS_AUTH_MODE_CHANGE_PASSWORD = 0x00000002
    static let TNS_AUTH_MODE_SYSDBA = 0x00000020
    static let TNS_AUTH_MODE_SYSOPER = 0x00000040
    static let TNS_AUTH_MODE_PRELIM = 0x00000080
    static let TNS_AUTH_MODE_WITH_PASSWORD = 0x00000100
    static let TNS_AUTH_MODE_SYSASM = 0x00400000
    static let TNS_AUTH_MODE_SYSBKP = 0x01000000
    static let TNS_AUTH_MODE_SYSDGD = 0x02000000
    static let TNS_AUTH_MODE_SYSKMT = 0x04000000
    static let TNS_AUTH_MODE_SYSRAC = 0x08000000
    static let TNS_AUTH_MODE_IAM_TOKEN = 0x20000000

    // MARK: Character sets and encodings
    static let TNS_CHARSET_UTF8 = 873
    static let TNS_CHARSET_UTF16 = 2000
    static let TNS_ENCODING_UTF8 = "UTF-8"
    static let TNS_ENCODING_UTF16 = "UTF-16BE"

    // MARK: Compile time capability indices
    static let TNS_CCAP_SQL_VERSION = 0
    static let TNS_CCAP_LOGON_TYPES = 4
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
    static let TNS_CCAP_MAX = 45

    // MARK: Compile time capability values
    static let TNS_CCAP_SQL_VERSION_MAX: UInt8 = 6
    static let TNS_CCAP_FIELD_VERSION_11_2 = 6
    static let TNS_CCAP_FIELD_VERSION_12_1 = 7
    static let TNS_CCAP_FIELD_VERSION_12_2 = 8
    static let TNS_CCAP_FIELD_VERSION_12_2_EXT1 = 9
    static let TNS_CCAP_FIELD_VERSION_18_1 = 10
    static let TNS_CCAP_FIELD_VERSION_18_1_EXT_1 = 11
    static let TNS_CCAP_FIELD_VERSION_19_1 = 12
    static let TNS_CCAP_FIELD_VERSION_19_1_EXT_1 = 13
    static let TNS_CCAP_FIELD_VERSION_20_1 = 14
    static let TNS_CCAP_FIELD_VERSION_20_1_EXT_1 = 15
    static let TNS_CCAP_FIELD_VERSION_21_1 = 16
    static let TNS_CCAP_FIELD_VERSION_MAX: UInt8 = 16
    static let TNS_CCAP_O5LOGON: UInt8 = 8
    static let TNS_CCAP_O5LOGON_NP: UInt8 = 2
    static let TNS_CCAP_O7LOGON: UInt8 = 32
    static let TNS_CCAP_O8LOGON_LONG_IDENTIFIER: UInt8 = 64
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
    static let TNS_CCAP_DRCP: UInt8 = 0x10
    static let TNS_CCAP_ZLNP: UInt8 = 0x04
    static let TNS_CCAP_INBAND_NOTIFICATION: UInt8 = 0x04
    static let TNS_CCAP_CLIENT_FN_MAX: UInt8 = 12

    // MARK: Runtime capability indices
    static let TNS_RCAP_COMPAT = 0
    static let TNS_RCAP_TTC = 6
    static let TNS_RCAP_MAX = 7

    // MARK: Runtime capability values
    static let TNS_RCAP_COMPAT_81: UInt8 = 2
    static let TNS_RCAP_TTC_ZERO_COPY: UInt8 = 0x01
    static let TNS_RCAP_TTC_32K: UInt8 = 0x04

    // MARK: Verifier types
    static let TNS_VERIFIER_TYPE_11G_1 = 0xb152
    static let TNS_VERIFIER_TYPE_11G_2 = 0x1b25
    static let TNS_VERIFIER_TYPE_12C = 0x4815

    // MARK: Other constants
    static let TNS_MAX_SHORT_LENGTH = 252
    static let TNS_ESCAPE_CHAR = 253
    static let TNS_LONG_LENGTH_INDICATOR = 254
    static let TNS_NULL_LENGTH_INDICATOR = 255
    static let TNS_MAX_ROWID_LENGTH = 18
    static let TNS_DURATION_MID = 0x80000000
    static let TNS_DURATION_OFFSET = 60
    static let TNS_DURATION_SESSION = 10
    static let TNS_MIN_LONG_LENGTH = 0x8000
    static let TNS_MAX_LONG_LENGTH = 0x7fffffff
    static let TNS_SDU: UInt16 = 8192
    static let TNS_TDU: UInt16 = 65535
    static let TNS_MAX_CURSORS_TO_CLOSE = 500
    static let TNS_TXN_IN_PROGRESS = 0x00000002
    static let TNS_MAX_CONNECT_DATA = 230
    static let TNS_CHUNK_SIZE = 32767
    static let TNS_MAX_UROWID_LENGTH = 5267

    // MARK: Base 64 encoding alphabet
    private static let TNS_ALPHABET_DATA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".data(using: .utf8)
    static let TNS_BASE64_ALPHABET = TNS_ALPHABET_DATA?.base64EncodedString()
    static let TNS_BASE64_ALPHABET_ARRAY = TNS_ALPHABET_DATA?.base64EncodedData()
    static let TNS_EXTENT_OID = Data(hex: "00000000000000000000000000010001")

    // MARK: Purity types
    static let PURITY_DEFAULT = 0
    static let PURITY_NEW = 1
    static let PURITY_SELF = 2

    // MARK: Timezone offsets
    static let TZ_HOUR_OFFSET = 20
    static let TZ_MINUTE_OFFSET = 60

    // MARK: DRCP release mode
    static let DRCP_DEAUTHENTICATE = 0x00000002

}

extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }

        let chars = hex.map { $0 }
        let bytes = stride(from: 0, to: chars.count, by: 2)
            .map { String(chars[$0]) + String(chars[$0 + 1]) }
            .compactMap { UInt8($0, radix: 16) }

        guard hex.count / bytes.count == 2 else { return nil }
        self.init(bytes)
    }
}
