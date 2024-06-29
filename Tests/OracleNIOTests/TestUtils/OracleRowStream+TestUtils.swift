//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOEmbedded

@testable import OracleNIO

extension OracleRowStream {

    convenience init(
        source: Source,
        eventLoop: any EventLoop = EmbeddedEventLoop()
    ) {
        self.init(
            source: source,
            eventLoop: eventLoop,
            logger: OracleConnection.noopLogger
        )
    }

}
