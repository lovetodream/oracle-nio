//
//  File.swift
//  
//
//  Created by Timo Zacherl on 07.04.23.
//

struct FetchInfo {
    var precision: Int16
    var scale: Int16
    var bufferSize: UInt32
    var size: UInt32
    var nullsAllowed: Bool
    var name: String
    var dbType: DBType
}
