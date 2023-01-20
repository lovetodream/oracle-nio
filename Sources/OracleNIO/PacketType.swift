/// TNS Packet Types
enum PacketType: UInt8, CustomStringConvertible {
    case connect = 1
    case accept = 2
    case refuse = 4
    case data = 6
    case resend = 11
    case marker = 12
    case control = 14
    case redirect = 5

    var description: String {
        switch self {
        case .connect: return "CONNECT"
        case .accept: return "ACCEPT"
        case .refuse: return "REFUSE"
        case .data: return "DATA"
        case .resend: return "RESEND"
        case .marker: return "MARKER"
        case .control: return "CONTROL"
        case .redirect: return "REDIRECT"
        }
    }
}
