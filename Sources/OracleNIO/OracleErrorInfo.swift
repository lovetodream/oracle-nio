//
//  OracleErrorInfo.swift
//  OracleNIO
//
//  Created by Timo Zacherl on 05.01.23.
//
//  Defining the various messages that are sent to the database and
//  the responses that are received by the client.
//

struct OracleErrorInfo {
    var number: UInt32
    var cursorID: UInt16
    var position: UInt16
    var rowCount: UInt64
    var isWarning: Bool
    var message: String
    var rowID: Any
    var batchErrors: Array<Any>
}
