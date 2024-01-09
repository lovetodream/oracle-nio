struct DataType: Sendable, Hashable {
    var dataType: _TNSDataType
    var convDataType: _TNSDataType
    var representation: DataType.Representation

    /// Data type representations
    enum Representation: UInt16, Sendable, Hashable, CustomStringConvertible {
        case native = 0
        case universal = 1
        case oracle = 10

        public var description: String {
            switch self {
            case .native:
                return "NATIVE"
            case .universal:
                return "UNIVERSAL"
            case .oracle:
                return "ORACLE"
            }
        }
    }

    /// The data type array sent to the database server during connect.
    static let all: [DataType] = [
        .init(dataType: .varchar, convDataType: .varchar, representation: .universal),
        .init(dataType: .number, convDataType: .number, representation: .oracle),
        .init(dataType: .long, convDataType: .long, representation: .universal),
        .init(dataType: .date, convDataType: .date, representation: .oracle),
        .init(dataType: .raw, convDataType: .raw, representation: .universal),
        .init(dataType: .longRAW, convDataType: .longRAW, representation: .universal),
        .init(dataType: .ub2, convDataType: .ub2, representation: .universal),
        .init(dataType: .ub4, convDataType: .ub4, representation: .universal),
        .init(dataType: .sb1, convDataType: .sb1, representation: .universal),
        .init(dataType: .sb2, convDataType: .sb2, representation: .universal),
        .init(dataType: .sb4, convDataType: .sb4, representation: .universal),
        .init(dataType: .sword, convDataType: .sword, representation: .universal),
        .init(dataType: .uword, convDataType: .uword, representation: .universal),
        .init(dataType: .ptrb, convDataType: .ptrb, representation: .universal),
        .init(dataType: .ptrw, convDataType: .ptrw, representation: .universal),
        .init(dataType: .tiddef, convDataType: .tiddef, representation: .universal),
        .init(dataType: .rowID, convDataType: .rowID, representation: .universal),
        .init(dataType: .ams, convDataType: .ams, representation: .universal),
        .init(dataType: .brn, convDataType: .brn, representation: .universal),
        .init(dataType: .cwd, convDataType: .cwd, representation: .universal),
        .init(dataType: .newOAC, convDataType: .newOAC, representation: .universal),
        .init(dataType: .oer8, convDataType: .oer8, representation: .universal),
        .init(dataType: .fun, convDataType: .fun, representation: .universal),
        .init(dataType: .aua, convDataType: .aua, representation: .universal),
        .init(dataType: .rxh7, convDataType: .rxh7, representation: .universal),
        .init(dataType: .na6, convDataType: .na6, representation: .universal),
        .init(dataType: .brp, convDataType: .brp, representation: .universal),
        .init(dataType: .brv, convDataType: .brv, representation: .universal),
        .init(dataType: .kva, convDataType: .kva, representation: .universal),
        .init(dataType: .cls, convDataType: .cls, representation: .universal),
        .init(dataType: .cui, convDataType: .cui, representation: .universal),
        .init(dataType: .dfn, convDataType: .dfn, representation: .universal),
        .init(dataType: .dqr, convDataType: .dqr, representation: .universal),
        .init(dataType: .dsc, convDataType: .dsc, representation: .universal),
        .init(dataType: .exe, convDataType: .exe, representation: .universal),
        .init(dataType: .fch, convDataType: .fch, representation: .universal),
        .init(dataType: .gbv, convDataType: .gbv, representation: .universal),
        .init(dataType: .gem, convDataType: .gem, representation: .universal),
        .init(dataType: .giv, convDataType: .giv, representation: .universal),
        .init(dataType: .okg, convDataType: .okg, representation: .universal),
        .init(dataType: .hmi, convDataType: .hmi, representation: .universal),
        .init(dataType: .ino, convDataType: .ino, representation: .universal),
        .init(dataType: .lnf, convDataType: .lnf, representation: .universal),
        .init(dataType: .ont, convDataType: .ont, representation: .universal),
        .init(dataType: .ope, convDataType: .ope, representation: .universal),
        .init(dataType: .osq, convDataType: .osq, representation: .universal),
        .init(dataType: .sfe, convDataType: .sfe, representation: .universal),
        .init(dataType: .spf, convDataType: .spf, representation: .universal),
        .init(dataType: .vsn, convDataType: .vsn, representation: .universal),
        .init(dataType: .ud7, convDataType: .ud7, representation: .universal),
        .init(dataType: .dsa, convDataType: .dsa, representation: .universal),
        .init(dataType: .pin, convDataType: .pin, representation: .universal),
        .init(dataType: .pfn, convDataType: .pfn, representation: .universal),
        .init(dataType: .ppt, convDataType: .ppt, representation: .universal),
        .init(dataType: .sto, convDataType: .sto, representation: .universal),
        .init(dataType: .arc, convDataType: .arc, representation: .universal),
        .init(dataType: .mrs, convDataType: .mrs, representation: .universal),
        .init(dataType: .mrt, convDataType: .mrt, representation: .universal),
        .init(dataType: .mrg, convDataType: .mrg, representation: .universal),
        .init(dataType: .mrr, convDataType: .mrr, representation: .universal),
        .init(dataType: .mrc, convDataType: .mrc, representation: .universal),
        .init(dataType: .ver, convDataType: .ver, representation: .universal),
        .init(dataType: .lon2, convDataType: .lon2, representation: .universal),
        .init(dataType: .ino2, convDataType: .ino2, representation: .universal),
        .init(dataType: .all, convDataType: .all, representation: .universal),
        .init(dataType: .udb, convDataType: .udb, representation: .universal),
        .init(dataType: .aqi, convDataType: .aqi, representation: .universal),
        .init(dataType: .ulb, convDataType: .ulb, representation: .universal),
        .init(dataType: .uld, convDataType: .uld, representation: .universal),
        .init(dataType: .sid, convDataType: .sid, representation: .universal),
        .init(dataType: .na7, convDataType: .na7, representation: .universal),
        .init(dataType: .al7, convDataType: .al7, representation: .universal),
        .init(dataType: .k2rpc, convDataType: .k2rpc, representation: .universal),
        .init(dataType: .xdp, convDataType: .xdp, representation: .universal),
        .init(dataType: .oko8, convDataType: .oko8, representation: .universal),
        .init(dataType: .ud12, convDataType: .ud12, representation: .universal),
        .init(dataType: .al8, convDataType: .al8, representation: .universal),
        .init(dataType: .lfop, convDataType: .lfop, representation: .universal),
        .init(dataType: .fcrt, convDataType: .fcrt, representation: .universal),
        .init(dataType: .dny, convDataType: .dny, representation: .universal),
        .init(dataType: .opr, convDataType: .opr, representation: .universal),
        .init(dataType: .pls, convDataType: .pls, representation: .universal),
        .init(dataType: .xid, convDataType: .xid, representation: .universal),
        .init(dataType: .txn, convDataType: .txn, representation: .universal),
        .init(dataType: .dcb, convDataType: .dcb, representation: .universal),
        .init(dataType: .cca, convDataType: .cca, representation: .universal),
        .init(dataType: .wrn, convDataType: .wrn, representation: .universal),
        .init(dataType: .tlh, convDataType: .tlh, representation: .universal),
        .init(dataType: .toh, convDataType: .toh, representation: .universal),
        .init(dataType: .foi, convDataType: .foi, representation: .universal),
        .init(dataType: .sid2, convDataType: .sid2, representation: .universal),
        .init(dataType: .tch, convDataType: .tch, representation: .universal),
        .init(dataType: .pii, convDataType: .pii, representation: .universal),
        .init(dataType: .pfi, convDataType: .pfi, representation: .universal),
        .init(dataType: .ppu, convDataType: .ppu, representation: .universal),
        .init(dataType: .pte, convDataType: .pte, representation: .universal),
        .init(dataType: .rxh8, convDataType: .rxh8, representation: .universal),
        .init(dataType: .n12, convDataType: .n12, representation: .universal),
        .init(dataType: .auth, convDataType: .auth, representation: .universal),
        .init(dataType: .kval, convDataType: .kval, representation: .universal),
        .init(dataType: .fgi, convDataType: .fgi, representation: .universal),
        .init(dataType: .dsy, convDataType: .dsy, representation: .universal),
        .init(dataType: .dsyr8, convDataType: .dsyr8, representation: .universal),
        .init(dataType: .dsyh8, convDataType: .dsyh8, representation: .universal),
        .init(dataType: .dsyl, convDataType: .dsyl, representation: .universal),
        .init(dataType: .dsyt8, convDataType: .dsyt8, representation: .universal),
        .init(dataType: .dsyv8, convDataType: .dsyv8, representation: .universal),
        .init(dataType: .dsyp, convDataType: .dsyp, representation: .universal),
        .init(dataType: .dsyf, convDataType: .dsyf, representation: .universal),
        .init(dataType: .dsyk, convDataType: .dsyk, representation: .universal),
        .init(dataType: .dsyy, convDataType: .dsyy, representation: .universal),
        .init(dataType: .dsyq, convDataType: .dsyq, representation: .universal),
        .init(dataType: .dsyc, convDataType: .dsyc, representation: .universal),
        .init(dataType: .dsya, convDataType: .dsya, representation: .universal),
        .init(dataType: .ot8, convDataType: .ot8, representation: .universal),
        .init(dataType: .dsyty, convDataType: .dsyty, representation: .universal),
        .init(dataType: .aqe, convDataType: .aqe, representation: .universal),
        .init(dataType: .kv, convDataType: .kv, representation: .universal),
        .init(dataType: .aqd, convDataType: .aqd, representation: .universal),
        .init(dataType: .aq8, convDataType: .aq8, representation: .universal),
        .init(dataType: .rfs, convDataType: .rfs, representation: .universal),
        .init(dataType: .rxh10, convDataType: .rxh10, representation: .universal),
        .init(dataType: .kpn, convDataType: .kpn, representation: .universal),
        .init(dataType: .kpdnr, convDataType: .kpdnr, representation: .universal),
        .init(dataType: .dsyd, convDataType: .dsyd, representation: .universal),
        .init(dataType: .dsys, convDataType: .dsys, representation: .universal),
        .init(dataType: .dsyr, convDataType: .dsyr, representation: .universal),
        .init(dataType: .dsyh, convDataType: .dsyh, representation: .universal),
        .init(dataType: .dsyt, convDataType: .dsyt, representation: .universal),
        .init(dataType: .dsyv, convDataType: .dsyv, representation: .universal),
        .init(dataType: .aqm, convDataType: .aqm, representation: .universal),
        .init(dataType: .oer11, convDataType: .oer11, representation: .universal),
        .init(dataType: .aql, convDataType: .aql, representation: .universal),
        .init(dataType: .otc, convDataType: .otc, representation: .universal),
        .init(dataType: .kfno, convDataType: .kfno, representation: .universal),
        .init(dataType: .kfnp, convDataType: .kfnp, representation: .universal),
        .init(dataType: .kgt8, convDataType: .kgt8, representation: .universal),
        .init(dataType: .rasb4, convDataType: .rasb4, representation: .universal),
        .init(dataType: .raub2, convDataType: .raub2, representation: .universal),
        .init(dataType: .raub1, convDataType: .raub1, representation: .universal),
        .init(dataType: .ratxt, convDataType: .ratxt, representation: .universal),
        .init(dataType: .rssb4, convDataType: .rssb4, representation: .universal),
        .init(dataType: .rsub2, convDataType: .rsub2, representation: .universal),
        .init(dataType: .rsub1, convDataType: .rsub1, representation: .universal),
        .init(dataType: .rstxt, convDataType: .rstxt, representation: .universal),
        .init(dataType: .ridl, convDataType: .ridl, representation: .universal),
        .init(dataType: .glrdd, convDataType: .glrdd, representation: .universal),
        .init(dataType: .glrdg, convDataType: .glrdg, representation: .universal),
        .init(dataType: .glrdc, convDataType: .glrdc, representation: .universal),
        .init(dataType: .oko, convDataType: .oko, representation: .universal),
        .init(dataType: .dpp, convDataType: .dpp, representation: .universal),
        .init(dataType: .dpls, convDataType: .dpls, representation: .universal),
        .init(dataType: .dpmop, convDataType: .dpmop, representation: .universal),
        .init(dataType: .stat, convDataType: .stat, representation: .universal),
        .init(dataType: .rfx, convDataType: .rfx, representation: .universal),
        .init(dataType: .fal, convDataType: .fal, representation: .universal),
        .init(dataType: .ckv, convDataType: .ckv, representation: .universal),
        .init(dataType: .drcx, convDataType: .drcx, representation: .universal),
        .init(dataType: .kgh, convDataType: .kgh, representation: .universal),
        .init(dataType: .aqo, convDataType: .aqo, representation: .universal),
        .init(dataType: .okgt, convDataType: .okgt, representation: .universal),
        .init(dataType: .kpfc, convDataType: .kpfc, representation: .universal),
        .init(dataType: .fe2, convDataType: .fe2, representation: .universal),
        .init(dataType: .spfp, convDataType: .spfp, representation: .universal),
        .init(dataType: .dpuls, convDataType: .dpuls, representation: .universal),
        .init(dataType: .aqa, convDataType: .aqa, representation: .universal),
        .init(dataType: .kpbf, convDataType: .kpbf, representation: .universal),
        .init(dataType: .tsm, convDataType: .tsm, representation: .universal),
        .init(dataType: .mss, convDataType: .mss, representation: .universal),
        .init(dataType: .kpc, convDataType: .kpc, representation: .universal),
        .init(dataType: .crs, convDataType: .crs, representation: .universal),
        .init(dataType: .kks, convDataType: .kks, representation: .universal),
        .init(dataType: .ksp, convDataType: .ksp, representation: .universal),
        .init(dataType: .ksptop, convDataType: .ksptop, representation: .universal),
        .init(dataType: .kspval, convDataType: .kspval, representation: .universal),
        .init(dataType: .pss, convDataType: .pss, representation: .universal),
        .init(dataType: .nls, convDataType: .nls, representation: .universal),
        .init(dataType: .als, convDataType: .als, representation: .universal),
        .init(dataType: .ksdevtval, convDataType: .ksdevtval, representation: .universal),
        .init(dataType: .ksdevttop, convDataType: .ksdevttop, representation: .universal),
        .init(dataType: .kpspp, convDataType: .kpspp, representation: .universal),
        .init(dataType: .kol, convDataType: .kol, representation: .universal),
        .init(dataType: .lst, convDataType: .lst, representation: .universal),
        .init(dataType: .acx, convDataType: .acx, representation: .universal),
        .init(dataType: .scs, convDataType: .scs, representation: .universal),
        .init(dataType: .rxh, convDataType: .rxh, representation: .universal),
        .init(dataType: .kpdns, convDataType: .kpdns, representation: .universal),
        .init(dataType: .kpdcn, convDataType: .kpdcn, representation: .universal),
        .init(dataType: .kpnns, convDataType: .kpnns, representation: .universal),
        .init(dataType: .kpncn, convDataType: .kpncn, representation: .universal),
        .init(dataType: .kps, convDataType: .kps, representation: .universal),
        .init(dataType: .apinf, convDataType: .apinf, representation: .universal),
        .init(dataType: .ten, convDataType: .ten, representation: .universal),
        .init(dataType: .xsscs, convDataType: .xsscs, representation: .universal),
        .init(dataType: .xssso, convDataType: .xssso, representation: .universal),
        .init(dataType: .xssao, convDataType: .xssao, representation: .universal),
        .init(dataType: .ksrpc, convDataType: .ksrpc, representation: .universal),
        .init(dataType: .kvl, convDataType: .kvl, representation: .universal),
        .init(dataType: .xssdef, convDataType: .xssdef, representation: .universal),
        .init(dataType: .pdqcinv, convDataType: .pdqcinv, representation: .universal),
        .init(dataType: .pdqidc, convDataType: .pdqidc, representation: .universal),
        .init(dataType: .kpdqcsta, convDataType: .kpdqcsta, representation: .universal),
        .init(dataType: .kprs, convDataType: .kprs, representation: .universal),
        .init(dataType: .kpdqidc, convDataType: .kpdqidc, representation: .universal),
        .init(dataType: .rtstrm, convDataType: .rtstrm, representation: .universal),
        .init(dataType: .sessget, convDataType: .sessget, representation: .universal),
        .init(dataType: .sessrel, convDataType: .sessrel, representation: .universal),
        .init(dataType: .sessret, convDataType: .sessret, representation: .universal),
        .init(dataType: .scn6, convDataType: .scn6, representation: .universal),
        .init(dataType: .kecpa, convDataType: .kecpa, representation: .universal),
        .init(dataType: .kecpp, convDataType: .kecpp, representation: .universal),
        .init(dataType: .sxa, convDataType: .sxa, representation: .universal),
        .init(dataType: .kvarr, convDataType: .kvarr, representation: .universal),
        .init(dataType: .kpngn, convDataType: .kpngn, representation: .universal),
        .init(dataType: .binaryInteger, convDataType: .number, representation: .oracle),
        .init(dataType: .float, convDataType: .number, representation: .oracle),
        .init(dataType: .str, convDataType: .varchar, representation: .universal),
        .init(dataType: .vnu, convDataType: .number, representation: .oracle),
        .init(dataType: .pdn, convDataType: .number, representation: .oracle),
        .init(dataType: .vsc, convDataType: .varchar, representation: .universal),
        .init(dataType: .vbi, convDataType: .varchar, representation: .universal),
        .init(dataType: .oac, convDataType: .newOAC, representation: .universal),
        .init(dataType: .uin, convDataType: .number, representation: .oracle),
        .init(dataType: .sls, convDataType: .number, representation: .oracle),
        .init(dataType: .lvc, convDataType: .varchar, representation: .universal),
        .init(dataType: .lvb, convDataType: .raw, representation: .universal),
        .init(dataType: .char, convDataType: .char, representation: .universal),
        .init(dataType: .avc, convDataType: .char, representation: .universal),
        .init(dataType: .binaryFloat, convDataType: .binaryFloat, representation: .universal),
        .init(dataType: .binaryDouble, convDataType: .binaryDouble, representation: .universal),
        .init(dataType: .cursor, convDataType: .cursor, representation: .universal),
        .init(dataType: .rdd, convDataType: .rowID, representation: .universal),
        .init(dataType: .osl, convDataType: .osl, representation: .universal),
        .init(dataType: .extNamed, convDataType: .intNamed, representation: .universal),
        .init(dataType: .intNamed, convDataType: .intNamed, representation: .universal),
        .init(dataType: .extRef, convDataType: .intRef, representation: .universal),
        .init(dataType: .intRef, convDataType: .intRef, representation: .universal),
        .init(dataType: .clob, convDataType: .clob, representation: .universal),
        .init(dataType: .blob, convDataType: .blob, representation: .universal),
        .init(dataType: .bfile, convDataType: .bfile, representation: .universal),
        .init(dataType: .cfile, convDataType: .cfile, representation: .universal),
        .init(dataType: .rset, convDataType: .cursor, representation: .universal),
        .init(dataType: .json, convDataType: .json, representation: .universal),
        .init(dataType: .dJSON, convDataType: .dJSON, representation: .universal),
        .init(dataType: .clv, convDataType: .clv, representation: .universal),
        .init(dataType: .dtr, convDataType: .number, representation: .oracle),
        .init(dataType: .dun, convDataType: .number, representation: .oracle),
        .init(dataType: .dop, convDataType: .number, representation: .oracle),
        .init(dataType: .vst, convDataType: .varchar, representation: .universal),
        .init(dataType: .odt, convDataType: .date, representation: .oracle),
        .init(dataType: .dol, convDataType: .number, representation: .oracle),
        .init(dataType: .time, convDataType: .time, representation: .universal),
        .init(dataType: .timeTZ, convDataType: .timeTZ, representation: .universal),
        .init(dataType: .timestamp, convDataType: .timestamp, representation: .universal),
        .init(dataType: .timestampTZ, convDataType: .timestampTZ, representation: .universal),
        .init(dataType: .intervalYM, convDataType: .intervalYM, representation: .universal),
        .init(dataType: .intervalDS, convDataType: .intervalDS, representation: .universal),
        .init(dataType: .eDate, convDataType: .date, representation: .oracle),
        .init(dataType: .eTime, convDataType: .eTime, representation: .universal),
        .init(dataType: .etTZ, convDataType: .etTZ, representation: .universal),
        .init(dataType: .eStamp, convDataType: .eStamp, representation: .universal),
        .init(dataType: .eStz, convDataType: .eStz, representation: .universal),
        .init(dataType: .eiym, convDataType: .eiym, representation: .universal),
        .init(dataType: .eids, convDataType: .eids, representation: .universal),
        .init(dataType: .dclob, convDataType: .clob, representation: .universal),
        .init(dataType: .dblob, convDataType: .blob, representation: .universal),
        .init(dataType: .dbfile, convDataType: .bfile, representation: .universal),
        .init(dataType: .uRowID, convDataType: .uRowID, representation: .universal),
        .init(dataType: .timestampLTZ, convDataType: .timestampLTZ, representation: .universal),
        .init(dataType: .esitz, convDataType: .timestampLTZ, representation: .universal),
        .init(dataType: .ub8, convDataType: .ub8, representation: .universal),
        .init(dataType: .pnty, convDataType: .intNamed, representation: .universal),
        .init(dataType: .boolean, convDataType: .boolean, representation: .universal),
        .init(dataType: .xsnsop, convDataType: .xsnsop, representation: .universal),
        .init(dataType: .xsattr, convDataType: .xsattr, representation: .universal),
        .init(dataType: .xsns, convDataType: .xsns, representation: .universal),
        .init(dataType: .ub1array, convDataType: .ub1array, representation: .universal),
        .init(dataType: .sessstate, convDataType: .sessstate, representation: .universal),
        .init(dataType: .acReplay, convDataType: .acReplay, representation: .universal),
        .init(dataType: .acCont, convDataType: .acCont, representation: .universal),
        .init(dataType: .implres, convDataType: .implres, representation: .universal),
        .init(dataType: .oer, convDataType: .oer, representation: .universal),
        .init(dataType: .txt, convDataType: .txt, representation: .universal),
        .init(dataType: .xssessns, convDataType: .xssessns, representation: .universal),
        .init(dataType: .xsattop, convDataType: .xsattop, representation: .universal),
        .init(dataType: .xscreop, convDataType: .xscreop, representation: .universal),
        .init(dataType: .xsdetop, convDataType: .xsdetop, representation: .universal),
        .init(dataType: .xsdesop, convDataType: .xsdesop, representation: .universal),
        .init(dataType: .xssetsp, convDataType: .xssetsp, representation: .universal),
        .init(dataType: .xssidp, convDataType: .xssidp, representation: .universal),
        .init(dataType: .xsprin, convDataType: .xsprin, representation: .universal),
        .init(dataType: .xskvl, convDataType: .xskvl, representation: .universal),
        .init(dataType: .xsssdef2, convDataType: .xsssdef2, representation: .universal),
        .init(dataType: .xsnsop2, convDataType: .xsnsop2, representation: .universal),
        .init(dataType: .xsns2, convDataType: .xsns2, representation: .universal),
        .init(dataType: .kpdnreq, convDataType: .kpdnreq, representation: .universal),
        .init(dataType: .kpdnrnf, convDataType: .kpdnrnf, representation: .universal),
        .init(dataType: .kpngnc, convDataType: .kpngnc, representation: .universal),
        .init(dataType: .kpnri, convDataType: .kpnri, representation: .universal),
        .init(dataType: .aqenq, convDataType: .aqenq, representation: .universal),
        .init(dataType: .aqdeq, convDataType: .aqdeq, representation: .universal),
        .init(dataType: .aqjms, convDataType: .aqjms, representation: .universal),
        .init(dataType: .kpdnrpay, convDataType: .kpdnrpay, representation: .universal),
        .init(dataType: .kpdnrack, convDataType: .kpdnrack, representation: .universal),
        .init(dataType: .kpdnrmp, convDataType: .kpdnrmp, representation: .universal),
        .init(dataType: .kpdnrdq, convDataType: .kpdnrdq, representation: .universal),
        .init(dataType: .scn, convDataType: .scn, representation: .universal),
        .init(dataType: .scn8, convDataType: .scn8, representation: .universal),
        .init(dataType: .chunkinfo, convDataType: .chunkinfo, representation: .universal),
        .init(dataType: .uds, convDataType: .uds, representation: .universal),
        .init(dataType: .tnp, convDataType: .tnp, representation: .universal),
        .init(dataType: .undefined, convDataType: .undefined, representation: .native)
    ]
}
