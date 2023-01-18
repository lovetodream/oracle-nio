//
//  File.swift
//  
//
//  Created by Timo Zacherl on 13.01.23.
//

import OracleNIO
import Foundation

var logger = Logger(label: "com.lovetodream.oraclenio")
logger.logLevel = .trace
let proto = OracleProtocol(group: .init(numberOfThreads: 1), logger: logger)
do {
    try proto.connectPhaseOne(connection: OracleConnection(), address: .init(ipAddress: "192.168.1.22", port: 1521))
} catch {
    print(error)
}

RunLoop.main.run()
