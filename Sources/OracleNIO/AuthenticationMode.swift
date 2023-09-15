/// Oracle authentication modes.
public enum AuthenticationMode: UInt32, CustomStringConvertible {
    case `default` = 0
    case prelim = 0x00000008
    case sysASM = 0x00008000
    case sysBKP = 0x00020000
    case sysDBA = 0x00000002
    case sysDGD = 0x00040000
    case sysKMT = 0x00080000
    case sysOPER = 0x00000004
    case sysRAC = 0x00100000

    public var description: String {
        switch self {
        case .default:
            return "DEFAULT"
        case .prelim:
            return "PRELIM"
        case .sysASM:
            return "SYSASM"
        case .sysBKP:
            return "SYSBKP"
        case .sysDBA:
            return "SYSDBA"
        case .sysDGD:
            return "SYSDGD"
        case .sysKMT:
            return "SYSKMT"
        case .sysOPER:
            return "SYSOPER"
        case .sysRAC:
            return "SYSRAC"
        }
    }

    /// Bitwise comparison.
    func compare(with other: Self) -> Bool {
        other.rawValue & self.rawValue != 0
    }
}
