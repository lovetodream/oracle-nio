import struct Foundation.Calendar
import struct Foundation.Date
import struct Foundation.DateComponents
import struct Foundation.TimeZone
import NIOCore

extension ByteBuffer {
    func parseDate(bytes: [UInt8], length: Int) throws -> Date? {
        var buffer = ByteBuffer(bytes: bytes)
        guard
            length >= 7,
            let firstSevenBytes = buffer.readBytes(length: 7)
        else { return nil }

        let year = (Int(firstSevenBytes[0]) - 100) * 100 + Int(firstSevenBytes[1]) - 100
        let month = Int(firstSevenBytes[2])
        let day = Int(firstSevenBytes[3])
        let hour = Int(firstSevenBytes[4]) - 1
        let minute = Int(firstSevenBytes[5]) - 1
        let second = Int(firstSevenBytes[6]) - 1

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )

        if length >= 11, let value = buffer.readInteger(endianness: .big, as: UInt32.self) {
            let fsecond = Double(value) / 1000.0
            components.nanosecond = Int(fsecond * 1_000_000_000)
        }

        let byte11 = buffer.readBytes(length: 1)?.first ?? 0
        let byte12 = buffer.readBytes(length: 1)?.first ?? 0

        if length > 11 && byte11 != 0 && byte12 != 0 {
            if byte11 & Constants.TNS_HAS_REGION_ID != 0 {
                throw OracleError.ErrorType.namedTimeZoneNotSupported
            }

            let tzHour = Int(byte11 - Constants.TZ_HOUR_OFFSET)
            let tzMinute = Int(byte12 - Constants.TZ_MINUTE_OFFSET)
            if tzHour != 0 || tzMinute != 0 {
                let timeZone = TimeZone(secondsFromGMT: tzHour * 3600 + tzMinute * 60)!
                components.timeZone = timeZone
            }
        }

        return calendar.date(from: components)
    }
}
