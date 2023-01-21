/// Server side piggyback operation codes
enum ServerPiggybackCode: UInt8, CustomStringConvertible {
    case queryCacheInvalidation = 1
    case osPidMts = 2
    case traceEvent = 3
    case sessRet = 4
    case sync = 5
    case ltxID = 7
    case acReplayContext = 8
    case extSync = 9

    var description: String {
        switch self {
        case .queryCacheInvalidation:
            return "QUERY_CACHE_INVALIDATION"
        case .osPidMts:
            return "OS_PID_MTS"
        case .traceEvent:
            return "TRACE_EVENT"
        case .sessRet:
            return "SESS_RET"
        case .sync:
            return "SYNC"
        case .ltxID:
            return "LTXID"
        case .acReplayContext:
            return "AC_REPLAY_CONTEXT"
        case .extSync:
            return "EXT_SYNC"
        }
    }
}
