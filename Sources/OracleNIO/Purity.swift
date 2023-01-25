/// Purity types.
enum Purity: UInt32, CustomStringConvertible {
    case `default` = 0
    case new = 1
    case `self` = 2

    var description: String {
        switch self {
        case .default:
            return "DEFAULT"
        case .new:
            return "NEW"
        case .self:
            return "SELF"
        }
    }
}
