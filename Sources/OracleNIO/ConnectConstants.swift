import Foundation

struct ConnectConstants {
    static let `default` = ConnectConstants()

    let programName = ProcessInfo.processInfo.processName
    let machineName = ProcessInfo.processInfo.hostName
    let pid = ProcessInfo.processInfo.processIdentifier
    let username = ProcessInfo.processInfo.userName
    let terminalName = "unknown"
    lazy var sanitizedProgramName = Self.sanitize(value: self.programName)
    lazy var sanitizedMachineName = Self.sanitize(value: self.machineName)
    lazy var sanitizedUsername = Self.sanitize(value: self.username)


    private static func sanitize(value: String) -> String {
        return value
            .replacingOccurrences(of: "(", with: "?")
            .replacingOccurrences(of: ")", with: "?")
            .replacingOccurrences(of: "=", with: "?")
    }
}
