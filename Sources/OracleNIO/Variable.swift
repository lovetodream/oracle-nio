import struct Foundation.Date
import struct Foundation.Decimal
import struct Foundation.TimeInterval

struct Variable {
    var dbType: DBType = .varchar
    var bufferSize: UInt32 = 0
    var isArray: Bool = false
    var numberOfElements: UInt32 = 0
    var numberOfElementsInArray: UInt32?
    var objectType: Any? // TODO: find out what this is
    var name: String?
    var size: UInt32 = 1
    var precision: Int16 = 0
    var scale: Int16 = 0
    var nullsAllowed: Bool = true
    var fetchInfo: FetchInfo? 
    var values: [Any?] = []
    var bypassDecode: Bool = false
    var lastRawValue: Any?

    mutating func finalizeInitialization() {
        if self.dbType.defaultSize > 0 {
            if self.size == 0 {
                self.size = UInt32(self.dbType.defaultSize)
            }
            self.bufferSize = self.size * UInt32(self.dbType.bufferSizeFactor)
        } else {
            self.bufferSize = UInt32(self.dbType.bufferSizeFactor)
        }
        if self.numberOfElements == 0 {
            self.numberOfElements = 1
        }

        self.values = .init(repeating: nil, count: Int(numberOfElements))
    }

    mutating func bind(cursor: Cursor, connection: OracleConnection, position: UInt32) throws {
        // for PL/SQL blocks, if the size of a string or bytes object exceeds
        // 32,767 bytes it must be converted to a BLOB/CLOB; and out converter
        // needs to be established as well to return the string in the way that
        // the user expects to get it
        if cursor.statement.isPlSQL && size > 32767 {
            if [.raw, .longRAW].contains(self.dbType.oracleType) {
                self.dbType = .blob
            } else if self.dbType.csfrm == Constants.TNS_CS_NCHAR {
                self.dbType = .nCLOB
            } else {
                self.dbType = .clob
            }
        }

        // for variables containing LOBs, create temporary LOBs, if needed
        if [.clob, .blob].contains(self.dbType.oracleType) {
            for (index, value) in values.enumerated() {
                if value != nil && value as? LOB == nil {
                    let lob = LOB.create(connection: connection, dbType: self.dbType)
                    if let value {
                        lob.write(value, offset: 0)
                    }
                    self.values[index] = lob
                }
            }
        }

        // bind by position
        let numberOfBinds = cursor.statement.bindInfoList.count
        let numberOfVariables = cursor.bindVariables.count
        if numberOfBinds != numberOfVariables {
            throw OracleError.ErrorType.wrongNumberOfPositionalBinds
        }
        var bindInfo = cursor.statement.bindInfoList[Int(position) - 1]
        try cursor.statement.setVariable(bindInfo: &bindInfo, variable: self, cursor: cursor)
        cursor.statement.bindInfoList[Int(position) - 1] = bindInfo
    }

    mutating func setValue(_ value: Any?, position: Int) {
        if !isArray {
            return self.setScalarValue(value, position: position)
        }

        guard let value = value as? [Any?] else { return }
        for (index, elementValue) in value.enumerated() {
            self.setScalarValue(elementValue, position: index)
        }
        numberOfElementsInArray = UInt32(value.count)
    }

    mutating func setScalarValue(_ value: Any?, position: Int) {
        values[position] = value
    }

    mutating func setTypeInfoFromValue(_ value: Any?, isPlSQL: Bool) {
        if value == nil {
            dbType = .varchar
            size = 1
        } else if let _ = value as? Bool {
            dbType = isPlSQL ? .boolean : .binaryInteger
        } else if let value = value as? String {
            dbType = .varchar
            size = UInt32(value.count)
        } else if let value = value as? [UInt8] {
            dbType = .raw
            size = UInt32(value.count)
        } else if let _ = value as? Int {
            dbType = .number
        } else if let _ = value as? Float {
            dbType = .number
        } else if let _ = value as? Double {
            dbType = .number
        } else if let _ = value as? Decimal {
            dbType = .number
        } else if let _ = value as? Date {
            dbType = .date
        } else if let _ = value as? TimeInterval {
            dbType = .intervalDS
        } else {
            fatalError("Value not supported")
        }
    }
}
