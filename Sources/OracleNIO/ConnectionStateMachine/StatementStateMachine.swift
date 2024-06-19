//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

struct StatementStateMachine {

    private enum State {
        case initialized(StatementContext)
        case describeInfoReceived(StatementContext, DescribeInfo)
        case streaming(
            StatementContext,
            DescribeInfo,
            OracleBackendMessage.RowHeader,
            RowStreamStateMachine
        )
        case streamingAndWaiting(
            StatementContext,
            DescribeInfo,
            OracleBackendMessage.RowHeader,
            RowStreamStateMachine,
            partial: ByteBuffer
        )
        /// Indicates that the current statement was cancelled and we want to drain
        /// rows from the connection ASAP.
        case drain([OracleColumn])

        case commandComplete
        case error(OracleSQLError)

        case modifying
    }

    enum Action {
        case sendExecute(StatementContext, DescribeInfo?)
        case sendReexecute(StatementContext, CleanupContext)
        case sendFetch(StatementContext)
        case sendFlushOutBinds

        case failStatement(EventLoopPromise<OracleRowStream>, with: OracleSQLError)
        case succeedStatement(EventLoopPromise<OracleRowStream>, StatementResult)

        case evaluateErrorAtConnectionLevel(OracleSQLError)

        case needMoreData

        case forwardRows([DataRow])
        case forwardStreamComplete([DataRow], cursorID: UInt16)
        /// Error payload and a optional cursor ID, which should be closed in a future roundtrip.
        case forwardStreamError(
            OracleSQLError,
            read: Bool,
            cursorID: UInt16? = nil,
            clientCancelled: Bool = false
        )
        case forwardCancelComplete

        case read
        case wait
    }

    private enum DataRowResult {
        case row(DataRow)
        case notEnoughData
    }

    private var state: State
    private var isCancelled: Bool

    init(statementContext: StatementContext) {
        self.isCancelled = false
        self.state = .initialized(statementContext)
    }

    mutating func start() -> Action {
        guard case .initialized(let statementContext) = state else {
            preconditionFailure(
                "Start should only be called, if the statement has been initialized"
            )
        }

        if case .cursor(let cursor, _) = statementContext.type {
            self.state = .describeInfoReceived(statementContext, cursor.describeInfo)
        }

        return .sendExecute(statementContext, nil)
    }

    mutating func cancel() -> Action {
        switch self.state {
        case .initialized:
            preconditionFailure(
                "Start must be called immediately after the statement was created"
            )

        case .describeInfoReceived(let context, _):
            guard !self.isCancelled else {
                return .wait
            }

            self.isCancelled = true
            switch context.type {
            case .ddl(let promise),
                .dml(let promise),
                .plsql(let promise),
                .query(let promise),
                .cursor(_, let promise),
                .plain(let promise):
                return .failStatement(promise, with: .statementCancelled)
            }

        case .streaming(_, let describeInfo, _, var streamStateMachine),
            .streamingAndWaiting(
                _, let describeInfo, _, var streamStateMachine, _
            ):
            precondition(!self.isCancelled)
            self.isCancelled = true
            self.state = .drain(describeInfo.columns)
            switch streamStateMachine.fail() {
            case .wait:
                return .forwardStreamError(
                    .statementCancelled, read: false, clientCancelled: true
                )
            case .read:
                return .forwardStreamError(
                    .statementCancelled, read: true, clientCancelled: true
                )
            }

        case .commandComplete, .error, .drain:
            // the stream has already finished
            return .wait

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func describeInfoReceived(_ describeInfo: DescribeInfo) -> Action {
        guard case .initialized(let context) = state else {
            preconditionFailure("Describe info should be the initial response")
        }

        self.avoidingStateMachineCoWVoid { state in
            state = .describeInfoReceived(context, describeInfo)
        }

        return .wait
    }

    mutating func rowHeaderReceived(
        _ rowHeader: OracleBackendMessage.RowHeader
    ) -> Action {
        switch self.state {
        case .describeInfoReceived(let context, let describeInfo):
            self.avoidingStateMachineCoWVoid { state in
                state = .streaming(context, describeInfo, rowHeader, .init())
            }

            switch context.type {
            case .ddl(let promise),
                .dml(let promise),
                .plsql(let promise),
                .query(let promise),
                .cursor(_, let promise),
                .plain(let promise):
                return .succeedStatement(
                    promise,
                    StatementResult(
                        value: .describeInfo(describeInfo.columns),
                        logger: context.logger
                    )
                )
            }

        case .streaming(
            let context, let describeInfo, let prevRowHeader, let streamState
        ):
            if prevRowHeader.bitVector == nil {
                self.avoidingStateMachineCoWVoid { state in
                    state = .streaming(
                        context, describeInfo, rowHeader, streamState
                    )
                }
            }
            return .wait

        case .drain:
            // This state might occur, if the client cancelled the statement,
            // but the server did not yet receive/process the cancellation
            // marker. Due to that it might send more data without knowing yet.
            return .wait

        case .initialized, .streamingAndWaiting, .error, .commandComplete:
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func rowDataReceived(
        _ rowData: OracleBackendMessage.RowData,
        capabilities: Capabilities
    ) -> Action {
        switch self.state {
        case .initialized(let context):
            let outBinds = context.statement.binds.metadata.compactMap(\.outContainer)
            guard !outBinds.isEmpty else { preconditionFailure() }
            var buffer = rowData.slice
            if context.isReturning {
                for outBind in outBinds {
                    outBind.storage.withLockedValue { $0 = nil }
                    let rowCount = buffer.readUB4() ?? 0
                    guard rowCount > 0 else {
                        continue
                    }

                    do {
                        for _ in 0..<rowCount {
                            try self.processBindData(
                                from: &buffer,
                                outBind: outBind,
                                capabilities: capabilities
                            )
                        }
                    } catch {
                        guard let error = error as? OracleSQLError else {
                            preconditionFailure("Unexpected error: \(error)")
                        }
                        return self.setAndFireError(error)
                    }
                }

                return self.moreDataReceived(
                    &buffer,
                    capabilities: capabilities,
                    context: context,
                    describeInfo: nil
                )
            } else {
                for outBind in outBinds {
                    outBind.storage.withLockedValue { $0 = nil }
                    do {
                        try self.processBindData(
                            from: &buffer,
                            outBind: outBind,
                            capabilities: capabilities
                        )
                    } catch {
                        guard let error = error as? OracleSQLError else {
                            preconditionFailure("Unexpected error: \(error)")
                        }
                        return self.setAndFireError(error)
                    }
                }

                return self.moreDataReceived(
                    &buffer,
                    capabilities: capabilities,
                    context: context,
                    describeInfo: nil
                )
            }

        case .streaming(let context, let describeInfo, _, _):
            var buffer = rowData.slice
            let action = self.rowDataReceived0(
                buffer: &buffer, capabilities: capabilities
            )

            switch action {
            case .wait:
                return self.moreDataReceived(
                    &buffer,
                    capabilities: capabilities,
                    context: context,
                    describeInfo: describeInfo
                )

            default:
                return action
            }

        case .drain:
            // This state might occur, if the client cancelled the statement,
            // but the server did not yet receive/process the cancellation
            // marker. Due to that it might send more data without knowing yet.
            return .wait

        default:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func bitVectorReceived(
        _ bitVector: OracleBackendMessage.BitVector
    ) -> Action {
        switch self.state {
        case .streaming(
            let context, let describeInfo, var rowHeader, let streamState
        ):
            rowHeader.bitVector = bitVector.bitVector
            self.avoidingStateMachineCoWVoid { state in
                state = .streaming(
                    context, describeInfo, rowHeader, streamState
                )
            }
            return .wait

        default:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func errorReceived(
        _ error: OracleBackendMessage.BackendError
    ) -> Action {

        let action: Action
        if Constants.TNS_ERR_NO_DATA_FOUND == error.number
            || Constants.TNS_ERR_ARRAY_DML_ERRORS == error.number
        {
            switch self.state {
            case .commandComplete, .error, .drain:
                return .wait  // stream has already finished
            case .initialized(let context),
                .describeInfoReceived(let context, _):
                context.cursorID = error.cursorID ?? context.cursorID

                self.avoidingStateMachineCoWVoid { state in
                    state = .commandComplete
                }

                switch context.type {
                case .query(let promise),
                    .plsql(let promise),
                    .dml(let promise),
                    .ddl(let promise),
                    .cursor(_, let promise),
                    .plain(let promise):
                    action = .succeedStatement(
                        promise, .init(value: .noRows, logger: context.logger)
                    )  // empty response
                }

            case .streaming(let context, _, _, var demandStateMachine),
                .streamingAndWaiting(let context, _, _, var demandStateMachine, _):
                context.cursorID = error.cursorID ?? context.cursorID

                self.avoidingStateMachineCoWVoid { state in
                    state = .commandComplete
                }

                let rows = demandStateMachine.end()
                action = .forwardStreamComplete(rows, cursorID: context.cursorID)

            case .modifying:
                preconditionFailure("Invalid state: \(self.state)")
            }
        } else if self.isCancelled && error.number == 1013 {
            self.state = .commandComplete
            action = .forwardCancelComplete
        } else if error.number == Constants.TNS_ERR_VAR_NOT_IN_SELECT_LIST,
            let cursor = error.cursorID
        {
            switch self.state {
            case .initialized(let context):
                context.cursorID = cursor

                switch context.type {
                case .query(let promise),
                    .plsql(let promise),
                    .dml(let promise),
                    .ddl(let promise),
                    .cursor(_, let promise),
                    .plain(let promise):
                    action = .failStatement(promise, with: .server(error))
                }
            default:
                action = .forwardStreamError(
                    .server(error), read: false, cursorID: cursor
                )
            }

            self.avoidingStateMachineCoWVoid { state in
                state = .error(.server(error))
            }
        } else if let cursor = error.cursorID,
            error.number != 0 && cursor != 0
        {
            let exception = getExceptionClass(for: Int32(error.number))
            switch self.state {
            case .initialized(let context):
                context.cursorID = cursor

                switch context.type {
                case .query(let promise),
                    .plsql(let promise),
                    .dml(let promise),
                    .ddl(let promise),
                    .cursor(_, let promise),
                    .plain(let promise):
                    action = .failStatement(promise, with: .server(error))
                }
            default:
                if exception != .integrityError {
                    action = .forwardStreamError(
                        .server(error), read: false, cursorID: cursor
                    )
                } else {
                    action = .forwardStreamError(
                        .server(error), read: false, cursorID: nil
                    )
                }
            }

            self.avoidingStateMachineCoWVoid { state in
                state = .error(.server(error))
            }
        } else {
            switch self.state {
            case .drain,
                .commandComplete,
                .error:
                preconditionFailure("This is impossible...")

            case .initialized(let context):
                if let cursorID = error.cursorID {
                    context.cursorID = cursorID
                }
                switch context.type {
                case .query(let promise),
                    .plsql(let promise),
                    .dml(let promise),
                    .ddl(let promise),
                    .cursor(_, let promise),
                    .plain(let promise):
                    action = .succeedStatement(
                        promise,
                        StatementResult(
                            value: .noRows, logger: context.logger
                        )
                    )
                }
                self.state = .commandComplete

            case .describeInfoReceived(let context, let describeInfo):
                if let cursorID = error.cursorID {
                    context.cursorID = cursorID
                }
                if describeInfo.columns.contains(where: {
                    [.clob, .nCLOB, .blob, .json, .vector].contains($0.dataType)
                }) {
                    context.requiresDefine = true
                    context.noPrefetch = true

                    if !context.options.fetchLOBs {
                        var describeInfo = describeInfo
                        self.avoidingStateMachineCoWVoid { state in
                            describeInfo.columns = describeInfo.columns.map {
                                if ![.blob, .clob, .nCLOB].contains($0.dataType) {
                                    return $0
                                }
                                var col = $0
                                if col.dataType == .blob {
                                    col.dataType = .longRAW
                                } else if col.dataType == .clob {
                                    col.dataType = .long
                                } else if col.dataType == .nCLOB {
                                    col.dataType = .longNVarchar
                                }
                                if col.dataType.defaultSize > 0 {
                                    if col.dataTypeSize == 0 {
                                        col.dataTypeSize =
                                            UInt32(col.dataType.defaultSize)
                                    }
                                    col.bufferSize =
                                        col.dataTypeSize * UInt32(col.dataType.bufferSizeFactor)
                                } else {
                                    col.bufferSize =
                                        UInt32(col.dataType.bufferSizeFactor)
                                }
                                return col
                            }
                            state = .describeInfoReceived(context, describeInfo)
                        }
                        action = .sendExecute(context, describeInfo)
                    } else {
                        action = .sendExecute(context, describeInfo)
                    }

                } else if error.number != 0 {
                    switch context.type {
                    case .query(let promise),
                        .plsql(let promise),
                        .dml(let promise),
                        .ddl(let promise),
                        .cursor(_, let promise),
                        .plain(let promise):
                        action = .failStatement(promise, with: .server(error))
                    }

                    self.avoidingStateMachineCoWVoid { state in
                        state = .error(.server(error))
                    }
                } else {
                    action = .sendFetch(context)
                }

            case .streaming(let statementContext, _, _, _),
                .streamingAndWaiting(let statementContext, _, _, _, _):
                // no error actually happened, we need more rows
                if let cursorID = error.cursorID {
                    statementContext.cursorID = cursorID
                }
                action = .sendFetch(statementContext)

            case .modifying:
                preconditionFailure("Invalid state: \(self.state)")
            }
        }

        return action
    }

    mutating func errorHappened(_ error: OracleSQLError) -> Action {
        return self.setAndFireError(error)
    }

    mutating func chunkReceived(
        _ buffer: ByteBuffer, capabilities: Capabilities
    ) -> Action {
        switch self.state {
        case .drain:
            // Could happen if we cancelled the statement while the database is
            // still sending stuff
            return .wait

        case .streamingAndWaiting(
            let statementContext,
            let describeInfo,
            let rowHeader,
            let streamState,
            var partial
        ):
            partial.writeImmutableBuffer(buffer)
            self.avoidingStateMachineCoWVoid { state in
                state = .streaming(
                    statementContext, describeInfo, rowHeader, streamState
                )
            }
            return self.moreDataReceived(
                &partial,
                capabilities: capabilities,
                context: statementContext,
                describeInfo: describeInfo
            )

        default:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func ioVectorReceived(
        _ vector: OracleBackendMessage.InOutVector
    ) -> Action {
        switch self.state {
        case .initialized(let context):
            guard context.statement.binds.count == vector.bindMetadata.count else {
                preconditionFailure(
                    """
                    mismatch in binds - sent: \(context.statement.binds.count), \
                    received: \(vector.bindMetadata.count)
                    """)
            }

            // we won't change the state
            return .wait

        case .describeInfoReceived,
            .streaming,
            .streamingAndWaiting,
            .drain,
            .commandComplete,
            .error:
            return self.errorHappened(
                .unexpectedBackendMessage(.ioVector(vector))
            )

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func flushOutBindsReceived() -> Action {
        switch self.state {
        case .initialized:
            // we won't change the state, flush out binds is just a confirmation
            // to indicate the server can cleanup out binds from the currently
            // failing DML, after that we receive the actual error in the next
            // round trip.
            return .sendFlushOutBinds

        case .describeInfoReceived,
            .streaming,
            .streamingAndWaiting,
            .drain,
            .commandComplete,
            .error:
            return self.errorHappened(
                .unexpectedBackendMessage(.flushOutBinds)
            )

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    // MARK: Consumer Actions

    mutating func requestFetch() -> Action {
        switch self.state {
        case .initialized(let context),
            .describeInfoReceived(let context, _),
            .streaming(let context, _, _, _),
            .streamingAndWaiting(let context, _, _, _, _):
            return .sendFetch(context)
        case .drain,
            .commandComplete,
            .error:
            preconditionFailure(
                "We can't send a fetch if the statement completed already"
            )
        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func requestStatementRows() -> Action {
        switch self.state {
        case .streaming(
            let statementContext,
            let describeInfo,
            let rowHeader,
            var demandStateMachine
        ):
            return self.avoidingStateMachineCoW { state in
                let action = demandStateMachine.demandMoreResponseBodyParts()
                state = .streaming(
                    statementContext, describeInfo, rowHeader, demandStateMachine
                )
                switch action {
                case .read:
                    return .read
                case .wait:
                    return .wait
                }
            }

        case .streamingAndWaiting, .drain, .describeInfoReceived:
            return .wait

        case .initialized:
            preconditionFailure(
                "Requested to consume next row without anything going on."
            )

        case .commandComplete, .error:
            preconditionFailure(
                """
                The stream is already closed or in a failure state; \
                rows can not be consumed at this time.
                """)

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    // MARK: Channel actions

    mutating func channelReadComplete() -> Action {
        switch self.state {
        case .initialized,
            .describeInfoReceived,
            .drain,
            .commandComplete,
            .error:
            return .wait

        case .streaming(
            let context, let describeInfo, let header, var demandStateMachine
        ):
            return self.avoidingStateMachineCoW { state in
                let rows = demandStateMachine.channelReadComplete()
                state = .streaming(
                    context, describeInfo, header, demandStateMachine
                )
                switch rows {
                case .some(let rows):
                    return .forwardRows(rows)
                case .none:
                    return .wait
                }
            }
        case .streamingAndWaiting(
            let context, let describeInfo, let header, var demandStateMachine,
            let partial
        ):
            return self.avoidingStateMachineCoW { state in
                let rows = demandStateMachine.channelReadComplete()
                state = .streamingAndWaiting(
                    context, describeInfo, header, demandStateMachine,
                    partial: partial
                )
                switch rows {
                case .some(let rows):
                    return .forwardRows(rows)
                case .none:
                    return .wait
                }
            }

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func readEventCaught() -> Action {
        switch self.state {
        case .streaming(
            let context, let describeInfo, let header, var demandStateMachine
        ):
            precondition(!self.isCancelled)
            return self.avoidingStateMachineCoW { state in
                let action = demandStateMachine.read()
                state = .streaming(
                    context, describeInfo, header, demandStateMachine
                )
                switch action {
                case .wait:
                    return .wait
                case .read:
                    return .read
                }
            }
        case .streamingAndWaiting(
            let context, let describeInfo, let header, var demandStateMachine,
            let partial
        ):
            precondition(!self.isCancelled)
            return self.avoidingStateMachineCoW { state in
                let action = demandStateMachine.read()
                state = .streamingAndWaiting(
                    context, describeInfo, header, demandStateMachine,
                    partial: partial
                )
                switch action {
                case .wait:
                    return .wait
                case .read:
                    return .read
                }
            }
        case .initialized,
            .commandComplete,
            .drain,
            .error,
            .describeInfoReceived:
            // we already have the complete stream received, now we are waiting
            // for a `readyForStatement` package. To receive this we need to read.
            return .read

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    // MARK: Private Methods

    private mutating func moreDataReceived(
        _ buffer: inout ByteBuffer,
        capabilities: Capabilities,
        context: StatementContext,
        describeInfo: DescribeInfo?
    ) -> Action {
        while buffer.readableBytes > 0 {
            // This is not ideal, but still not as bad as passing potentially
            // huge buffers around as associated values in enums and causing
            // potential stack overflows when having big array sizes configured.
            // Reason for this even existing is that the `row data` response
            // from the Oracle database doesn't contain a length field you can
            // read without parsing all the values of said row. And to parse the
            // values you have to have contextual information from
            // `DescribeInfo`. So, because Oracle is sending messages in bulk,
            // we don't really have another choice.
            var slice = buffer.slice()
            let startReaderIndex = slice.readerIndex
            do {
                let decodingContext = OracleBackendMessageDecoder.Context(
                    capabilities: capabilities)
                decodingContext.statementOptions = context.options
                decodingContext.columnsCount = describeInfo?.columns.count
                var messages: TinySequence<OracleBackendMessage> = []
                try OracleBackendMessage.decodeData(
                    from: &slice,
                    into: &messages,
                    context: decodingContext
                )

                for message in messages {
                    let action: Action
                    switch message {
                    case .bitVector(let bitVector):
                        action = self.bitVectorReceived(bitVector)
                    case .describeInfo(let describeInfo):
                        action = self.describeInfoReceived(describeInfo)
                    case .rowHeader(let rowHeader):
                        action = self.rowHeaderReceived(rowHeader)
                    case .rowData(let rowData):
                        buffer = rowData.slice
                        action = self.rowDataReceived0(
                            buffer: &buffer, capabilities: capabilities
                        )
                    case .queryParameter:
                        // query parameters can be safely ignored
                        action = .wait
                    case .error(let error):
                        action = self.errorReceived(error)
                    case .flushOutBinds:
                        action = self.flushOutBindsReceived()
                    default:
                        preconditionFailure("Invalid state: \(self.state)")
                    }
                    // If action is anything other than wait, we will have to
                    // return it. This should be fine, because messages with
                    // an action should only occur at the end of a packet.
                    // At least thats what I (@lovetodream) know from testing.
                    if case .wait = action {
                        continue
                    }
                    return action
                }

                continue
            } catch let error as OraclePartialDecodingError {
                slice.moveReaderIndex(to: startReaderIndex)
                let completeMessage = slice.slice()
                let error = OracleSQLError.messageDecodingFailure(
                    .withPartialError(
                        error,
                        packetID: OracleBackendMessage.ID.data.rawValue,
                        messageBytes: completeMessage
                    )
                )
                return self.errorHappened(error)
            } catch {
                preconditionFailure(
                    "Expected to only see `OraclePartialDecodingError`s here."
                )
            }
        }

        return .wait
    }

    private mutating func rowDataReceived0(
        buffer: inout ByteBuffer, capabilities: Capabilities
    ) -> Action {
        switch self.state {
        case .streaming(
            let context, let describeInfo, var rowHeader, var demandStateMachine
        ):
            let readerIndex = buffer.readerIndex
            do {
                switch try self.rowDataReceived(
                    buffer: &buffer,
                    describeInfo: describeInfo,
                    rowHeader: &rowHeader,
                    capabilities: capabilities,
                    demandStateMachine: &demandStateMachine
                ) {
                case .row(let row):
                    demandStateMachine.receivedRow(row)
                    self.avoidingStateMachineCoWVoid { state in
                        state = .streaming(
                            context, describeInfo, rowHeader, demandStateMachine
                        )
                    }
                case .notEnoughData:
                    buffer.moveReaderIndex(to: readerIndex)
                    // prepend message id prefix again
                    var partial = ByteBuffer(
                        bytes: [OracleBackendMessage.MessageID.rowData.rawValue]
                    )
                    partial.writeImmutableBuffer(buffer.slice())

                    self.avoidingStateMachineCoWVoid { state in
                        state = .streamingAndWaiting(
                            context,
                            describeInfo,
                            rowHeader,
                            demandStateMachine,
                            partial: partial
                        )
                    }
                    return .needMoreData
                }
            } catch {
                guard let error = error as? OracleSQLError else {
                    preconditionFailure("Unexpected error: \(error)")
                }
                return self.setAndFireError(error)
            }

        default:
            preconditionFailure("Invalid state: \(self.state)")
        }

        return .wait
    }

    private mutating func setAndFireError(_ error: OracleSQLError) -> Action {
        switch self.state {
        case .initialized(let context),
            .describeInfoReceived(let context, _):
            if self.isCancelled {
                return .evaluateErrorAtConnectionLevel(error)
            } else {
                switch context.type {
                case .ddl(let promise),
                    .dml(let promise),
                    .plsql(let promise),
                    .query(let promise),
                    .cursor(_, let promise),
                    .plain(let promise):
                    self.state = .error(error)
                    return .failStatement(promise, with: error)
                }
            }

        case .drain:
            self.state = .error(error)
            return .evaluateErrorAtConnectionLevel(error)

        case .streaming(_, _, _, var streamState),
            .streamingAndWaiting(_, _, _, var streamState, _):
            self.state = .error(error)
            switch streamState.fail() {
            case .read:
                return .forwardStreamError(error, read: true, cursorID: nil)
            case .wait:
                return .forwardStreamError(error, read: false, cursorID: nil)
            }

        case .commandComplete, .error:
            preconditionFailure(
                """
                This state must not be reached. If the statement `.isComplete`,
                the ConnectionStateMachine must not send any further events to
                the substate machine.
                """)

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    // MARK: - Private helper methods -

    private func isDuplicateData(
        columnNumber: UInt32, bitVector: [UInt8]?
    ) -> Bool {
        guard let bitVector else { return false }
        let byteNumber = columnNumber / 8
        let bitNumber = columnNumber % 8
        return bitVector[Int(byteNumber)] & (1 << bitNumber) == 0
    }

    private func processBindData(
        from buffer: inout ByteBuffer,
        outBind: OracleRef,
        capabilities: Capabilities
    ) throws {
        let metadata = outBind.metadata.withLockedValue { $0 }
        guard
            var columnData = try self.processColumnData(
                from: &buffer,
                oracleType: metadata.dataType._oracleType,
                csfrm: metadata.dataType.csfrm,
                bufferSize: metadata.bufferSize,
                capabilities: capabilities
            )
        else {
            preconditionFailure(
                """
                unhandled need more data in bind processing: please file a issue \
                on https://github.com/lovetodream/oracle-nio/issues with steps to \
                reproduce the crash
                """)
        }

        let actualBytesCount = buffer.readSB4() ?? 0
        if actualBytesCount < 0 && metadata.dataType._oracleType == .boolean {
            return
        } else if actualBytesCount != 0 && !columnData.oracleColumnIsEmpty {
            // TODO: throw this as error?
            preconditionFailure("column truncated, length: \(actualBytesCount)")
        }

        outBind.storage.withLockedValue { storage in
            if storage == nil {
                storage = columnData
            } else {
                storage!.writeBuffer(&columnData)
            }
        }
    }

    private func processColumnData(
        from buffer: inout ByteBuffer,
        oracleType: _TNSDataType?,
        csfrm: UInt8,
        bufferSize: UInt32,
        capabilities: Capabilities
    ) throws -> ByteBuffer? {
        var columnValue: ByteBuffer
        if bufferSize == 0 && ![.long, .longRAW, .uRowID].contains(oracleType) {
            columnValue = ByteBuffer(bytes: [0])  // NULL indicator
            return columnValue
        }

        if [.varchar, .char, .long].contains(oracleType) {
            if csfrm == Constants.TNS_CS_NCHAR {
                try capabilities.checkNCharsetID()
            }
            // if we need capabilities during decoding in the future, we should
            // move this to decoding too
        }

        switch oracleType {
        case .varchar, .char, .long, .raw, .longRAW, .number, .date, .timestamp,
            .timestampLTZ, .timestampTZ, .rowID, .binaryDouble, .binaryFloat,
            .binaryInteger, .boolean, .intervalDS:
            switch buffer.readOracleSlice() {
            case .some(let slice):
                columnValue = slice
            case .none:
                return nil  // need more data
            }
        case .cursor:
            buffer.moveReaderIndex(forwardBy: 1)  // length (fixed value)

            let readerIndex = buffer.readerIndex
            _ = try DescribeInfo._decode(
                from: &buffer, context: .init(capabilities: capabilities)
            )
            buffer.skipUB2()  // cursor id
            let length = buffer.readerIndex - readerIndex
            buffer.moveReaderIndex(to: readerIndex)
            columnValue = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
            try columnValue.writeLengthPrefixed(as: UInt32.self) { base in
                let start = base.writerIndex
                try capabilities.encode(into: &base)
                base.writeImmutableBuffer(buffer.readSlice(length: length)!)
                return base.writerIndex - start
            }
            columnValue.writeInteger(0, as: UInt32.self)  // chunk length of zero
        case .clob, .blob:

            // LOB has a UB4 length indicator instead of the usual UInt8
            let length = try buffer.throwingReadUB4()
            if length > 0 {
                let size = try buffer.throwingReadUB8()
                let chunkSize = try buffer.throwingReadUB4()
                var locator = try buffer.readOracleSpecificLengthPrefixedSlice()
                columnValue = ByteBuffer()
                columnValue.writeInteger(size)
                columnValue.writeInteger(chunkSize)
                columnValue.writeBuffer(&locator)
            } else {
                columnValue = .init(bytes: [0])  // empty buffer
            }
        case .json:
            // TODO: OSON
            // OSON has a UB4 length indicator instead of the usual UInt8
            fatalError("OSON is not yet implemented, will be added in the future")
        case .vector:
            let length = try buffer.throwingReadUB4()
            if length > 0 {
                buffer.skipUB8()  // size (unused)
                buffer.skipUB4()  // chunk size (unused)
                switch buffer.readOracleSlice() {
                case .some(let slice):
                    columnValue = slice
                case .none:
                    return nil  // need more data
                }
                buffer.skipRawBytesChunked()  // LOB locator (unused)
            } else {
                columnValue = .init(bytes: [0])  // empty buffer
            }
        case .intNamed:
            let startIndex = buffer.readerIndex
            if try buffer.throwingReadUB4() > 0 {
                buffer.skipRawBytesChunked()  // type oid
            }
            if try buffer.throwingReadUB4() > 0 {
                buffer.skipRawBytesChunked()  // oid
            }
            if try buffer.throwingReadUB4() > 0 {
                buffer.skipRawBytesChunked()  // snapshot
            }
            buffer.skipUB2()  // version
            let dataLength = try buffer.throwingReadUB4()
            buffer.skipUB2()  // flags
            if dataLength > 0 {
                buffer.skipRawBytesChunked()  // data
            }
            let endIndex = buffer.readerIndex
            buffer.moveReaderIndex(to: startIndex)
            columnValue = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
            let length = (endIndex - startIndex) + (MemoryLayout<UInt32>.size * 2)
            columnValue.reserveCapacity(minimumWritableBytes: length)
            try columnValue.writeLengthPrefixed(as: UInt32.self) {
                $0.writeImmutableBuffer(buffer.readSlice(length: endIndex - startIndex)!)
            }
            columnValue.writeInteger(0, as: UInt32.self)  // chunk length of zero
        default:
            fatalError(
                "\(String(reflecting: oracleType)) is not implemented, please file a bug report")
        }

        if [.long, .longRAW].contains(oracleType) {
            buffer.skipSB4()  // null indicator
            buffer.skipUB4()  // return code
        }

        return columnValue
    }

    private mutating func rowDataReceived(
        buffer: inout ByteBuffer,
        describeInfo: DescribeInfo,
        rowHeader: inout OracleBackendMessage.RowHeader,
        capabilities: Capabilities,
        demandStateMachine: inout RowStreamStateMachine
    ) throws -> DataRowResult {
        var out = ByteBuffer()
        for (index, column) in describeInfo.columns.enumerated() {
            if self.isDuplicateData(
                columnNumber: UInt32(index), bitVector: rowHeader.bitVector
            ) {
                var data = demandStateMachine.receivedDuplicate(at: index)
                // write data with length, because demandStateMachine doesn't
                // return the length field
                try out.writeLengthPrefixed(as: UInt8.self) { buffer in
                    buffer.writeBuffer(&data)
                }
            } else if var data = try self.processColumnData(
                from: &buffer,
                oracleType: column.dataType._oracleType,
                csfrm: column.dataType.csfrm,
                bufferSize: column.bufferSize,
                capabilities: capabilities
            ) {
                out.writeBuffer(&data)
            } else {
                return .notEnoughData
            }
        }

        let data = DataRow(
            columnCount: describeInfo.columns.count, bytes: out
        )
        rowHeader.bitVector = nil  // reset bit vector after usage

        return .row(data)
    }

    var isComplete: Bool {
        switch self.state {
        case .initialized,
            .describeInfoReceived,
            .streaming,
            .streamingAndWaiting,
            .drain:
            return false
        case .commandComplete, .error:
            return true

        case .modifying:
            preconditionFailure("invalid state")
        }
    }
}

extension StatementStateMachine {
    /// While the state machine logic above is great, there is a downside to having all of the state machine
    /// data in associated data on enumerations: any modification of that data will trigger copy on write
    /// for heap-allocated data. That means that for _every operation on the state machine_ we will CoW
    /// our underlying state, which is not good.
    ///
    /// The way we can avoid this is by using this helper function. It will temporarily set state to a value with
    /// no associated data, before attempting the body of the function. It will also verify that the state
    /// machine never remains in this bad state.
    ///
    /// A key note here is that all callers must ensure that they return to a good state before they exit.
    private mutating func avoidingStateMachineCoW(
        _ body: (inout State) -> Action
    ) -> Action {
        self.state = .modifying
        defer {
            assert(!self.isModifying)
        }

        return body(&self.state)
    }

    private mutating func avoidingStateMachineCoWVoid(
        _ body: (inout State) -> Void
    ) {
        self.state = .modifying
        defer {
            assert(!self.isModifying)
        }

        return body(&self.state)
    }

    private var isModifying: Bool {
        if case .modifying = self.state {
            return true
        } else {
            return false
        }
    }
}
