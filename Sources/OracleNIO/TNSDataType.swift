/// A data type used by the TNS wire protocol.
public enum TNSDataType: UInt16, Sendable, Hashable, CustomStringConvertible {
    case undefined = 0
    case varchar = 1
    case number = 2
    case binaryInteger = 3
    case float = 4
    case str = 5
    case vnu = 6
    case pdn = 7
    case long = 8
    case vsc = 9
    case tiddef = 10
    case rowID = 11
    case date = 12
    case vbi = 15
    case raw = 23
    case longRAW = 24
    case ub2 = 25
    case ub4 = 26
    case sb1 = 27
    case sb2 = 28
    case sb4 = 29
    case sword = 30
    case uword = 31
    case ptrb = 32
    case ptrw = 33
    case oer8 = 290 // 34 + 256
    case fun = 291 // 35 + 256
    case aua = 292 // 36 + 256
    case rxh7 = 293 // 37 + 256
    case na6 = 294 // 38 + 256
    case oac = 39
    case ams = 40
    case brn = 41
    case brp = 298 // 42 + 256
    case brv = 299 // 43 + 256
    case kva = 300 // 44 + 256
    case cls = 301 // 45 + 256
    case cui = 302 // 46 + 256
    case dfn = 303 // 47 + 256
    case dqr = 304 // 48 + 256
    case dsc = 305 // 49 + 256
    case exe = 306 // 50 + 256
    case fch = 307 // 51 + 256
    case gbv = 308 // 52 + 256
    case gem = 309 // 53 + 256
    case giv = 310 // 54 + 256
    case okg = 311 // 55 + 256
    case hmi = 312 // 56 + 256
    case ino = 313 // 57 + 256
    case lnf = 315 // 59 + 256
    case ont = 316 // 60 + 256
    case ope = 317 // 61 + 256
    case osq = 318 // 62 + 256
    case sfe = 319 // 63 + 256
    case spf = 320 // 64 + 256
    case vsn = 321 // 65 + 256
    case ud7 = 322 // 66 + 256
    case dsa = 323 // 67 + 256
    case uin = 68
    case pin = 327 // 71 + 256
    case pfn = 328 // 72 + 256
    case ppt = 329 // 73 + 256
    case sto = 331 // 75 + 256
    case arc = 333 // 77 + 256
    case mrs = 334 // 78 + 256
    case mrt = 335 // 79 + 256
    case mrg = 336 // 80 + 256
    case mrr = 337 // 81 + 256
    case mrc = 338 // 82 + 256
    case ver = 339 // 83 + 256
    case lon2 = 340 // 84 + 256
    case ino2 = 341 // 85 + 256
    case all = 342 // 86 + 256
    case udb = 343 // 87 + 256
    case aqi = 344 // 88 + 256
    case ulb = 345 // 89 + 256
    case uld = 346 // 90 + 256
    case sls = 91
    case sid = 348 // 92 + 256
    case na7 = 349 // 93 + 256
    case lvc = 94
    case lvb = 95
    case char = 96
    case avc = 97
    case al7 = 354 // 98 + 256
    case k2rpc = 355 // 99 + 256
    case binaryFloat = 100
    case binaryDouble = 101
    case cursor = 102
    case rdd = 104
    case xdp = 359 // 103 + 256
    case osl = 106
    case oko8 = 363 // 107 + 256
    case extNamed = 108
    case intNamed = 109
    case extRef = 110
    case intRef = 111
    case clob = 112
    case blob = 113
    case bfile = 114
    case cfile = 115
    case rset = 116
    case cwd = 117
    case json = 119
    case newOAC = 120
    case ud12 = 380 // 124 + 256
    case al8 = 381 // 125 + 256
    case lfop = 382 // 126 + 256
    case fcrt = 383 // 127 + 256
    case dny = 384 // 128 + 256
    case opr = 385 // 129 + 256
    case pls = 386 // 130 + 256
    case xid = 387 // 131 + 256
    case txn = 388 // 132 + 256
    case dcb = 389 // 133 + 256
    case cca = 390 // 134 + 256
    case wrn = 391 // 135 + 256
    case tlh = 393 // 137 + 256
    case toh = 394 // 138 + 256
    case foi = 395 // 139 + 256
    case sid2 = 396 // 140 + 256
    case tch = 397 // 141 + 256
    case pii = 398 // 142 + 256
    case pfi = 399 // 143 + 256
    case ppu = 400 // 144 + 256
    case pte = 401 // 145 + 256
    case clv = 146
    case rxh8 = 404 // 148 + 256
    case n12 = 405 // 149 + 256
    case auth = 406 // 150 + 256
    case kval = 407 // 151 + 256
    case dtr = 152
    case dun = 153
    case dop = 154
    case vst = 155
    case odt = 156
    case fgi = 413 // 157 + 256
    case dsy = 414 // 158 + 256
    case dsyr8 = 415 // 159 + 256
    case dsyh8 = 416 // 160 + 256
    case dsyl = 417 // 161 + 256
    case dsyt8 = 418 // 162 + 256
    case dsyv8 = 419 // 163 + 256
    case dsyp = 420 // 164 + 256
    case dsyf = 421 // 165 + 256
    case dsyk = 422 // 166 + 256
    case dsyy = 423 // 167 + 256
    case dsyq = 424 // 168 + 256
    case dsyc = 425 // 169 + 256
    case dsya = 426 // 170 + 256
    case ot8 = 427 // 171 + 256
    case dol = 172
    case dsyty = 429 // 173 + 256
    case aqe = 430 // 174 + 256
    case kv = 431 // 175 + 256
    case aqd = 432 // 176 + 256
    case aq8 = 433 // 177 + 256
    case time = 178
    case timeTZ = 179
    case timestamp = 180
    case timestampTZ = 181
    case intervalYM = 182
    case intervalDS = 183
    case eDate = 184
    case eTime = 185
    case etTZ = 186
    case eStamp = 187
    case eStz = 188
    case eiym = 189
    case eids = 190
    case rfs = 449 // 193 + 256
    case rxh10 = 450 // 194 + 256
    case dclob = 195
    case dblob = 196
    case dbfile = 197
    case dJSON = 198
    case kpn = 454 // 198 + 256
    case kpdnr = 455 // 199 + 256
    case dsyd = 456 // 200 + 256
    case dsys = 457 // 201 + 256
    case dsyr = 458 // 202 + 256
    case dsyh = 459 // 203 + 256
    case dsyt = 460 // 204 + 256
    case dsyv = 461 // 205 + 256
    case aqm = 462 // 206 + 256
    case oer11 = 463 // 207 + 256
    case uRowID = 208
    case aql = 466 // 210 + 256
    case otc = 467 // 211 + 256
    case kfno = 468 // 212 + 256
    case kfnp = 469 // 213 + 256
    case kgt8 = 470 // 214 + 256
    case rasb4 = 471 // 215 + 256
    case raub2 = 472 // 216 + 256
    case raub1 = 473 // 217 + 256
    case ratxt = 474 // 218 + 256
    case rssb4 = 475 // 219 + 256
    case rsub2 = 476 // 220 + 256
    case rsub1 = 477 // 221 + 256
    case rstxt = 478 // 222 + 256
    case ridl = 479 // 223 + 256
    case glrdd = 480 // 224 + 256
    case glrdg = 481 // 225 + 256
    case glrdc = 482 // 226 + 256
    case oko = 483 // 227 + 256
    case dpp = 484 // 228 + 256
    case dpls = 485 // 229 + 256
    case dpmop = 486 // 230 + 256
    case timestampLTZ = 231
    case esitz = 232
    case ub8 = 233
    case stat = 490 // 234 + 256
    case rfx = 491 // 235 + 256
    case fal = 492 // 236 + 256
    case ckv = 493 // 237 + 256
    case drcx = 494 // 238 + 256
    case kgh = 495 // 239 + 256
    case aqo = 496 // 240 + 256
    case pnty = 241
    case okgt = 498 // 242 + 256
    case kpfc = 499 // 243 + 256
    case fe2 = 500 // 244 + 256
    case spfp = 501 // 245 + 256
    case dpuls = 502 // 246 + 256
    case boolean = 252
    case aqa = 509 // 253 + 256
    case kpbf = 510 // 254 + 256
    case tsm = 513
    case mss = 514
    case kpc = 516
    case crs = 517
    case kks = 518
    case ksp = 519
    case ksptop = 520
    case kspval = 521
    case pss = 522
    case nls = 523
    case als = 524
    case ksdevtval = 525
    case ksdevttop = 526
    case kpspp = 527
    case kol = 528
    case lst = 529
    case acx = 530
    case scs = 531
    case rxh = 532
    case kpdns = 533
    case kpdcn = 534
    case kpnns = 535
    case kpncn = 536
    case kps = 537
    case apinf = 538
    case ten = 539
    case xsscs = 540
    case xssso = 541
    case xssao = 542
    case ksrpc = 543
    case kvl = 560
    case sessget = 563
    case sessrel = 564
    case xssdef = 565
    case pdqcinv = 572
    case pdqidc = 573
    case kpdqcsta = 574
    case kprs = 575
    case kpdqidc = 576
    case rtstrm = 578
    case sessret = 579
    case scn6 = 580
    case kecpa = 581
    case kecpp = 582
    case sxa = 583
    case kvarr = 584
    case kpngn = 585
    case xsnsop = 590
    case xsattr = 591
    case xsns = 592
    case txt = 593
    case xssessns = 594
    case xsattop = 595
    case xscreop = 596
    case xsdetop = 597
    case xsdesop = 598
    case xssetsp = 599
    case xssidp = 600
    case xsprin = 601
    case xskvl = 602
    case xsssdef2 = 603
    case xsnsop2 = 604
    case xsns2 = 605
    case implres = 611
    case oer = 612
    case ub1array = 613
    case sessstate = 614
    case acReplay = 615
    case acCont = 616
    case kpdnreq = 622
    case kpdnrnf = 623
    case kpngnc = 624
    case kpnri = 625
    case aqenq = 626
    case aqdeq = 627
    case aqjms = 628
    case kpdnrpay = 629
    case kpdnrack = 630
    case kpdnrmp = 631
    case kpdnrdq = 632
    case chunkinfo = 636
    case scn = 637
    case scn8 = 638
    case uds = 639
    case tnp = 640

    public var description: String {
        switch self {
        case .undefined:
            return "UNDEFINED"
        case .varchar:
            return "VARCHAR"
        case .number:
            return "NUMBER"
        case .binaryInteger:
            return "BINARY_INTEGER"
        case .float:
            return "FLOAT"
        case .str:
            return "STR"
        case .vnu:
            return "VNU"
        case .pdn:
            return "PDN"
        case .long:
            return "LONG"
        case .vsc:
            return "VCS"
        case .tiddef:
            return "TIDDEF"
        case .rowID:
            return "ROWID"
        case .date:
            return "DATE"
        case .vbi:
            return "VBI"
        case .raw:
            return "RAW"
        case .longRAW:
            return "LONG_RAW"
        case .ub2:
            return "UB2"
        case .ub4:
            return "UB4"
        case .sb1:
            return "SB1"
        case .sb2:
            return "SB2"
        case .sb4:
            return "SB4"
        case .sword:
            return "SWORD"
        case .uword:
            return "UWORD"
        case .ptrb:
            return "PTRB"
        case .ptrw:
            return "PTRW"
        case .oer8:
            return "OER8"
        case .fun:
            return "FUN"
        case .aua:
            return "AUA"
        case .rxh7:
            return "RXH7"
        case .na6:
            return "NA6"
        case .oac:
            return "OAC"
        case .ams:
            return "AMS"
        case .brn:
            return "BRN"
        case .brp:
            return "BRP"
        case .brv:
            return "BRV"
        case .kva:
            return "KVA"
        case .cls:
            return "CLS"
        case .cui:
            return "CUI"
        case .dfn:
            return "DFN"
        case .dqr:
            return "DQR"
        case .dsc:
            return "DSC"
        case .exe:
            return "EXE"
        case .fch:
            return "FCH"
        case .gbv:
            return "GBV"
        case .gem:
            return "GEM"
        case .giv:
            return "GIV"
        case .okg:
            return "OKG"
        case .hmi:
            return "HMI"
        case .ino:
            return "INO"
        case .lnf:
            return "LNF"
        case .ont:
            return "ONT"
        case .ope:
            return "OPE"
        case .osq:
            return "OSQ"
        case .sfe:
            return "SFE"
        case .spf:
            return "SPF"
        case .vsn:
            return "VSN"
        case .ud7:
            return "UD7"
        case .dsa:
            return "DSA"
        case .uin:
            return "UIN"
        case .pin:
            return "PIN"
        case .pfn:
            return "PFN"
        case .ppt:
            return "PPT"
        case .sto:
            return "STO"
        case .arc:
            return "ARC"
        case .mrs:
            return "MRS"
        case .mrt:
            return "MRT"
        case .mrg:
            return "MRG"
        case .mrr:
            return "MRR"
        case .mrc:
            return "MRC"
        case .ver:
            return "VER"
        case .lon2:
            return "LON2"
        case .ino2:
            return "INO2"
        case .all:
            return "ALL"
        case .udb:
            return "UDB"
        case .aqi:
            return "AQI"
        case .ulb:
            return "ULB"
        case .uld:
            return "ULD"
        case .sls:
            return "SLS"
        case .sid:
            return "SID"
        case .na7:
            return "NA7"
        case .lvc:
            return "LVC"
        case .lvb:
            return "LVB"
        case .char:
            return "CHAR"
        case .avc:
            return "AVC"
        case .al7:
            return "AL7"
        case .k2rpc:
            return "K2RPC"
        case .binaryFloat:
            return "BINARY_FLOAT"
        case .binaryDouble:
            return "BINARY_DOUBLE"
        case .cursor:
            return "CURSOR"
        case .rdd:
            return "RDD"
        case .xdp:
            return "XDP"
        case .osl:
            return "OSL"
        case .oko8:
            return "OKO8"
        case .extNamed:
            return "EXT_NAMED"
        case .intNamed:
            return "INT_NAMED"
        case .extRef:
            return "EXT_REF"
        case .intRef:
            return "INT_REF"
        case .clob:
            return "CLOB"
        case .blob:
            return "BLOB"
        case .bfile:
            return "BFILE"
        case .cfile:
            return "CFILE"
        case .rset:
            return "RSET"
        case .cwd:
            return "CWD"
        case .json:
            return "JSON"
        case .newOAC:
            return "NEW_OAC"
        case .ud12:
            return "UD12"
        case .al8:
            return "AL8"
        case .lfop:
            return "LFOP"
        case .fcrt:
            return "FCRT"
        case .dny:
            return "DNY"
        case .opr:
            return "OPR"
        case .pls:
            return "PLS"
        case .xid:
            return "XID"
        case .txn:
            return "TXN"
        case .dcb:
            return "DCB"
        case .cca:
            return "CCA"
        case .wrn:
            return "WRN"
        case .tlh:
            return "TLH"
        case .toh:
            return "TOH"
        case .foi:
            return "FOI"
        case .sid2:
            return "SID2"
        case .tch:
            return "TCH"
        case .pii:
            return "PII"
        case .pfi:
            return "PFI"
        case .ppu:
            return "PPU"
        case .pte:
            return "PTE"
        case .clv:
            return "CLV"
        case .rxh8:
            return "RXH8"
        case .n12:
            return "N12"
        case .auth:
            return "AUTH"
        case .kval:
            return "KVAL"
        case .dtr:
            return "DTR"
        case .dun:
            return "DUN"
        case .dop:
            return "DOP"
        case .vst:
            return "VST"
        case .odt:
            return "ODT"
        case .fgi:
            return "FGI"
        case .dsy:
            return "DSY"
        case .dsyr8:
            return "DSYR8"
        case .dsyh8:
            return "DSYH8"
        case .dsyl:
            return "DSYL"
        case .dsyt8:
            return "DSYT8"
        case .dsyv8:
            return "DSYV8"
        case .dsyp:
            return "DSYP"
        case .dsyf:
            return "DSYF"
        case .dsyk:
            return "DSYK"
        case .dsyy:
            return "DSYY"
        case .dsyq:
            return "DSYQ"
        case .dsyc:
            return "DSYC"
        case .dsya:
            return "DSYA"
        case .ot8:
            return "OT8"
        case .dol:
            return "DOL"
        case .dsyty:
            return "DSYTY"
        case .aqe:
            return "AQE"
        case .kv:
            return "KV"
        case .aqd:
            return "AQD"
        case .aq8:
            return "AQ8"
        case .time:
            return "TIME"
        case .timeTZ:
            return "TIME_TZ"
        case .timestamp:
            return "TIMESTAMP"
        case .timestampTZ:
            return "TIMESTAMP_TZ"
        case .intervalYM:
            return "INTERVAL_YM"
        case .intervalDS:
            return "INTERVAL_DS"
        case .eDate:
            return "EDATE"
        case .eTime:
            return "ETIME"
        case .etTZ:
            return "ETTZ"
        case .eStamp:
            return "ESTAMP"
        case .eStz:
            return "ESTZ"
        case .eiym:
            return "EIYM"
        case .eids:
            return "EIDS"
        case .rfs:
            return "RFS"
        case .rxh10:
            return "RXH10"
        case .dclob:
            return "DCLOB"
        case .dblob:
            return "DBLOB"
        case .dbfile:
            return "DBFILE"
        case .dJSON:
            return "DJSON"
        case .kpn:
            return "KPN"
        case .kpdnr:
            return "KPDNR"
        case .dsyd:
            return "DSYD"
        case .dsys:
            return "DSYS"
        case .dsyr:
            return "DSYR"
        case .dsyh:
            return "DSYH"
        case .dsyt:
            return "DSYT"
        case .dsyv:
            return "DSYV"
        case .aqm:
            return "AQM"
        case .oer11:
            return "OER11"
        case .uRowID:
            return "UROWID"
        case .aql:
            return "AQL"
        case .otc:
            return "OTC"
        case .kfno:
            return "KFNO"
        case .kfnp:
            return "KFNP"
        case .kgt8:
            return "KGT8"
        case .rasb4:
            return "RASB4"
        case .raub2:
            return "RAUB2"
        case .raub1:
            return "RAUB1"
        case .ratxt:
            return "RATXT"
        case .rssb4:
            return "RSSB4"
        case .rsub2:
            return "RSUB2"
        case .rsub1:
            return "RSUB1"
        case .rstxt:
            return "RSTXT"
        case .ridl:
            return "RIDL"
        case .glrdd:
            return "GLRDD"
        case .glrdg:
            return "GLRDG"
        case .glrdc:
            return "GLRDC"
        case .oko:
            return "OKO"
        case .dpp:
            return "DPP"
        case .dpls:
            return "DPLS"
        case .dpmop:
            return "DPMOP"
        case .timestampLTZ:
            return "TIMESTAMP_LTZ"
        case .esitz:
            return "ESITZ"
        case .ub8:
            return "UB8"
        case .stat:
            return "STAT"
        case .rfx:
            return "RFX"
        case .fal:
            return "FAL"
        case .ckv:
            return "CKV"
        case .drcx:
            return "DRCX"
        case .kgh:
            return "KGH"
        case .aqo:
            return "AQO"
        case .pnty:
            return "PNTY"
        case .okgt:
            return "OKGT"
        case .kpfc:
            return "KPFC"
        case .fe2:
            return "FE2"
        case .spfp:
            return "SPFP"
        case .dpuls:
            return "DPULS"
        case .boolean:
            return "BOOLEAN"
        case .aqa:
            return "AQA"
        case .kpbf:
            return "KPBF"
        case .tsm:
            return "TSM"
        case .mss:
            return "MSS"
        case .kpc:
            return "KPC"
        case .crs:
            return "CRS"
        case .kks:
            return "KKS"
        case .ksp:
            return "KSP"
        case .ksptop:
            return "KSPTOP"
        case .kspval:
            return "KSPVAL"
        case .pss:
            return "PSS"
        case .nls:
            return "NLS"
        case .als:
            return "ALS"
        case .ksdevtval:
            return "KSDEVTVAL"
        case .ksdevttop:
            return "KSDEVTTOP"
        case .kpspp:
            return "KPSPP"
        case .kol:
            return "KOL"
        case .lst:
            return "LST"
        case .acx:
            return "ACX"
        case .scs:
            return "SCS"
        case .rxh:
            return "RXH"
        case .kpdns:
            return "KPDNS"
        case .kpdcn:
            return "KPDCN"
        case .kpnns:
            return "KPNNS"
        case .kpncn:
            return "KPNCN"
        case .kps:
            return "KPS"
        case .apinf:
            return "APINF"
        case .ten:
            return "TEN"
        case .xsscs:
            return "XSSCS"
        case .xssso:
            return "XSSSO"
        case .xssao:
            return "XSSAO"
        case .ksrpc:
            return "KSRPC"
        case .kvl:
            return "KVL"
        case .sessget:
            return "SESSGET"
        case .sessrel:
            return "SESSREL"
        case .xssdef:
            return "XSSDEF"
        case .pdqcinv:
            return "PDQCINV"
        case .pdqidc:
            return "PDQIDC"
        case .kpdqcsta:
            return "KPDQCSTA"
        case .kprs:
            return "KPRS"
        case .kpdqidc:
            return "KPDQIDC"
        case .rtstrm:
            return "RTSTRM"
        case .sessret:
            return "SESSRET"
        case .scn6:
            return "SCN6"
        case .kecpa:
            return "KECPA"
        case .kecpp:
            return "KECPP"
        case .sxa:
            return "SXA"
        case .kvarr:
            return "KVARR"
        case .kpngn:
            return "KPNGN"
        case .xsnsop:
            return "XSNSOP"
        case .xsattr:
            return "XSATTR"
        case .xsns:
            return "XSNS"
        case .txt:
            return "TXT"
        case .xssessns:
            return "XSSESSNS"
        case .xsattop:
            return "XSATTOP"
        case .xscreop:
            return "XSCREOP"
        case .xsdetop:
            return "XSDETOP"
        case .xsdesop:
            return "XSDESOP"
        case .xssetsp:
            return "XSSETSP"
        case .xssidp:
            return "XSSIDP"
        case .xsprin:
            return "XSPRIN"
        case .xskvl:
            return "XSKVL"
        case .xsssdef2:
            return "XSSSDEF2"
        case .xsnsop2:
            return "XSNSOP2"
        case .xsns2:
            return "XSNS2"
        case .implres:
            return "IMPLRES"
        case .oer:
            return "OER"
        case .ub1array:
            return "UB1ARRAY"
        case .sessstate:
            return "SESSSTATE"
        case .acReplay:
            return "AC_REPLAY"
        case .acCont:
            return "AC_CONT"
        case .kpdnreq:
            return "KPDNREQ"
        case .kpdnrnf:
            return "KPDNRNF"
        case .kpngnc:
            return "KPNGNC"
        case .kpnri:
            return "KPNRI"
        case .aqenq:
            return "AQENQ"
        case .aqdeq:
            return "AQDEQ"
        case .aqjms:
            return "AQJMS"
        case .kpdnrpay:
            return "KPDNRPAY"
        case .kpdnrack:
            return "KPDNRACK"
        case .kpdnrmp:
            return "KPDNRMP"
        case .kpdnrdq:
            return "KPDNRDQ"
        case .chunkinfo:
            return "CHUNKINFO"
        case .scn:
            return "SCN"
        case .scn8:
            return "SCN8"
        case .uds:
            return "UDS"
        case .tnp:
            return "TNP"
        }
    }
    }
