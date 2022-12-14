import ODPIC
import struct Foundation.Calendar
import struct Foundation.DateComponents
import struct Foundation.TimeZone

internal struct OracleStatement {
    private var handle: OpaquePointer?
    private let connection: OracleConnection

    private var variables = [OpaquePointer?]()

    internal init(query: String, on connection: OracleConnection) throws {
        guard let cHandle = connection.handle else {
            throw OracleError(reason: .noHandle, message: "The db handle is not available, the connection is most likely already closed")
        }
        self.connection = connection
        guard dpiConn_prepareStmt(cHandle, 0, query, UInt32(query.count), nil, 0, &handle) == DPI_SUCCESS else {
            connection.logger.debug("Failed to prepare statement")
            throw OracleError.getLast(for: connection)
        }
        connection.logger.debug("Statement successfully prepared")
    }

    internal mutating func bind(_ binds: [OracleData]) throws {
        for (i, bind) in binds.enumerated() {
            let i = UInt32(i + 1)
            switch bind {
            case .integer(let value):
                var data = dpiData(isNull: 0, value: dpiDataBuffer(asInt64: Int64(value)))
                guard dpiStmt_bindValueByPos(handle, i, dpiNativeTypeNum(DPI_NATIVE_TYPE_INT64), &data) == DPI_SUCCESS else {
                    throw OracleError.getLast(for: connection)
                }
            case .float(let value):
                var data = dpiData(isNull: 0, value: dpiDataBuffer(asFloat: value))
                guard dpiStmt_bindValueByPos(handle, i, dpiNativeTypeNum(DPI_NATIVE_TYPE_FLOAT), &data) == DPI_SUCCESS else {
                    throw OracleError.getLast(for: connection)
                }
            case .double(let value):
                var data = dpiData(isNull: 0, value: dpiDataBuffer(asDouble: value))
                guard dpiStmt_bindValueByPos(handle, i, dpiNativeTypeNum(DPI_NATIVE_TYPE_DOUBLE), &data) == DPI_SUCCESS else {
                    throw OracleError.getLast(for: connection)
                }
            case .text(let value):
                try value.withCString {
                    let bytes = dpiBytes(ptr: UnsafeMutablePointer(mutating: $0), length: UInt32(value.count), encoding: nil)
                    var data = dpiData(isNull: 0, value: dpiDataBuffer(asBytes: bytes))
                    guard dpiStmt_bindValueByPos(handle, i, dpiNativeTypeNum(DPI_NATIVE_TYPE_BYTES), &data) == DPI_SUCCESS else {
                        throw OracleError.getLast(for: connection)
                    }
                }
            case .timestamp(let value):
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .timeZone], from: value)
                guard
                    let tzOffset = components.timeZone?.secondsFromGMT(),
                    let year = components.year,
                    let month = components.month,
                    let day = components.day,
                    let hour = components.hour,
                    let minute = components.minute,
                    let second = components.second,
                    let nanosecond = components.nanosecond
                else {
                    throw OracleError(reason: .error, message: "Couldn't extract date required components from \(value)")
                }
                let tzHourOffset = tzOffset / 3600
                let tzMinuteOffset = abs(tzOffset / 60) % 60
                let timestamp = dpiTimestamp(
                    year: Int16(year),
                    month: UInt8(month),
                    day: UInt8(day),
                    hour: UInt8(hour),
                    minute: UInt8(minute),
                    second: UInt8(second),
                    fsecond: UInt32(nanosecond),
                    tzHourOffset: Int8(tzHourOffset),
                    tzMinuteOffset: Int8(tzMinuteOffset)
                )
                var data = dpiData(isNull: 0, value: dpiDataBuffer(asTimestamp: timestamp))
                guard dpiStmt_bindValueByPos(handle, i, dpiNativeTypeNum(DPI_NATIVE_TYPE_TIMESTAMP), &data) == DPI_SUCCESS else {
                    throw OracleError.getLast(for: connection)
                }
            case .blob(var value):
                try value.withUnsafeMutableReadableBytes { pointer in
                    var data = dpiData(isNull: 0, value: dpiDataBuffer(asRaw: pointer.baseAddress))
                    guard dpiStmt_bindValueByPos(handle, i, dpiNativeTypeNum(DPI_NATIVE_TYPE_LOB), &data) == DPI_SUCCESS else {
                        throw OracleError.getLast(for: connection)
                    }
                }
            case .null:
                var data = dpiData(isNull: 1, value: dpiDataBuffer())
                guard dpiStmt_bindValueByPos(handle, i, dpiNativeTypeNum(DPI_NATIVE_TYPE_NULL), &data) == DPI_SUCCESS else {
                    throw OracleError.getLast(for: connection)
                }
            case .raw(var value):
                var data = value.withUnsafeMutableReadableBytes { pointer in
                    return dpiData(isNull: 0, value: dpiDataBuffer(asRaw: pointer.baseAddress))
                }
                let variable = try withUnsafeMutablePointer(to: &data) { pointer in
                    var variable: OpaquePointer?
                    var ptr: UnsafeMutablePointer<dpiData>? = pointer
                    guard dpiConn_newVar(connection.handle, dpiOracleTypeNum(DPI_ORACLE_TYPE_RAW), dpiNativeTypeNum(DPI_NATIVE_TYPE_BYTES), 0, UInt32(value.readableBytes), 1, 0, nil, &variable, &ptr) != 0 else {
                        throw OracleError.getLast(for: connection)
                    }
                    return variable
                }
                self.variables.append(variable)
                guard dpiStmt_bindByPos(handle, i, variable) == DPI_SUCCESS else {
                    throw OracleError.getLast(for: connection)
                }
            }
        }
    }

    internal func execute() throws {
        var numberOfQueryColumns: UInt32 = 0
        guard dpiStmt_execute(handle, dpiExecMode(DPI_MODE_EXEC_DEFAULT), &numberOfQueryColumns) == DPI_SUCCESS else {
            throw OracleError.getLast(for: connection)
        }
    }

    internal func columns() throws -> OracleColumnOffsets {
        var columns: [(String, Int)] = []

        var count: UInt32 = 0
        guard dpiStmt_getNumQueryColumns(handle, &count) == DPI_SUCCESS else {
            throw OracleError.getLast(for: connection)
        }
        connection.logger.debug("Total amount of columns: \(count)")

        // iterate over column count and initialize columns once
        // we will then re-use the columns for each row
        for i in 0..<count {
            try columns.append((self.column(at: Int32(i + 1)), numericCast(i)))
        }

        return .init(offsets: columns)
    }

    internal func nextRow(for columns: OracleColumnOffsets) throws -> OracleRow? {
        // step over the query, this will continue to return ORACLE_ROW
        // for as long as there are new rows to be fetched
        var found: Int32 = 0
        var bufferRowIndex: UInt32 = 0
        guard dpiStmt_fetch(handle, &found, &bufferRowIndex) == DPI_SUCCESS else {
            throw OracleError.getLast(for: connection)
        }

        if found == 0 {
            // cleanup
            for variable in variables {
                guard dpiVar_release(variable) == DPI_SUCCESS else {
                    throw OracleError.getLast(for: connection)
                }
            }
            guard dpiStmt_release(handle) == DPI_SUCCESS else {
                throw OracleError.getLast(for: connection)
            }
            return nil
        }

        var count: UInt32 = 0
        guard dpiStmt_getNumQueryColumns(handle, &count) == DPI_SUCCESS else {
            throw OracleError.getLast(for: connection)
        }
        var row: [OracleData] = []
        for i in 0..<count {
            try row.append(data(at: Int32(i + 1)))
        }
        return OracleRow(columnOffsets: columns, data: row)
    }

    // MARK: - Private

    private func data(at offset: Int32) throws -> OracleData {
        var nativeType = dpiNativeTypeNum()
        var value: UnsafeMutablePointer<dpiData>?
        guard dpiStmt_getQueryValue(handle, UInt32(offset), &nativeType, &value) == DPI_SUCCESS else {
            throw OracleError.getLast(for: connection)
        }
        var queryInfo = dpiQueryInfo()
        guard dpiStmt_getQueryInfo(handle, UInt32(offset), &queryInfo) == DPI_SUCCESS else {
            throw OracleError.getLast(for: connection)
        }
        guard let value else { throw OracleError.getLast(for: connection) }
        let type = try dataType(for: nativeType, and: queryInfo.typeInfo)
        switch type {
        case .integer:
            let val = value.pointee.value.asInt64
            let integer = Int(val)
            return .integer(integer)
        case .float:
            let float = value.pointee.value.asFloat
            return .float(float)
        case .double:
            let double = value.pointee.value.asDouble
            return .double(double)
        case .text:
            guard let val = value.pointee.value.asString else {
                throw OracleError(reason: .error, message: "Unexpected nil column text")
            }
            let string = String(cString: val)
            return .text(string)
        case .timestamp:
            let timestamp = value.pointee.value.asTimestamp
            let tzOffset = ((timestamp.tzHourOffset * 60) + timestamp.tzMinuteOffset) * 60

            let timeZone = TimeZone(secondsFromGMT: Int(tzOffset))
            guard let date = DateComponents(
                calendar: .current,
                timeZone: timeZone,
                year: Int(timestamp.year),
                month: Int(timestamp.month),
                day: Int(timestamp.day),
                hour: Int(timestamp.hour),
                minute: Int(timestamp.minute),
                second: Int(timestamp.second),
                nanosecond: Int(timestamp.fsecond)
            ).date else {
                throw OracleError(reason: .error, message: "Couldn't encode a valid date from timestamp")
            }
            return .timestamp(date)
        case .blob:
            let bytes = value.pointee.value.asBytes
            let length = Int(bytes.length)
            var buffer = ByteBufferAllocator().buffer(capacity: length)
            let pointer = UnsafeRawBufferPointer(start: bytes.ptr, count: length)
            buffer.writeBytes(pointer)
            return .blob(buffer)
        case .raw:
            let raw = value.pointee.value.asRaw.load(as: [UInt8].self)
            var buffer = ByteBufferAllocator().buffer(capacity: raw.count)
            buffer.writeBytes(raw)
            return .raw(buffer)
        case .null: return .null
        }
    }

    private func dataType(for nativeType: dpiNativeTypeNum, and oracleTypeInfo: dpiDataTypeInfo) throws -> OracleDataType {
        switch nativeType {
        case UInt32(DPI_NATIVE_TYPE_INT64): return .integer
        case UInt32(DPI_NATIVE_TYPE_FLOAT): return .float
        case UInt32(DPI_NATIVE_TYPE_DOUBLE): return .double
        case UInt32(DPI_NATIVE_TYPE_BYTES):
            if
                oracleTypeInfo.oracleTypeNum == DPI_ORACLE_TYPE_RAW ||
                oracleTypeInfo.oracleTypeNum == DPI_ORACLE_TYPE_LONG_RAW
            {
                return .raw
            }
            return .text
        case UInt32(DPI_NATIVE_TYPE_TIMESTAMP): return .timestamp
        case UInt32(DPI_NATIVE_TYPE_LOB): return .blob
        case UInt32(DPI_NATIVE_TYPE_NULL): return .null
        default: throw OracleError(reason: .error, message: "Unexpected column type: \(nativeType.description)")
        }
    }

    private func column(at offset: Int32) throws -> String {
        var queryInfo = dpiQueryInfo()
        guard dpiStmt_getQueryInfo(handle, UInt32(offset), &queryInfo) == DPI_SUCCESS else {
            throw OracleError.getLast(for: connection)
        }
        return String(cString: queryInfo.name)
    }
}
