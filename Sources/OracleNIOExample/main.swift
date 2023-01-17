//
//  File.swift
//  
//
//  Created by Timo Zacherl on 13.01.23.
//

import OracleNIO

let proto = OracleProtocol(group: .init(numberOfThreads: 1))
do {
    try proto.connectPhaseOne(connection: OracleConnection(), address: .init(ipAddress: "192.168.1.22", port: 1521))
} catch {
    print(error)
}
