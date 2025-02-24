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

struct StatementStateMachine {

    private enum State {
        case initialized(StatementContext)
        case rowCountsReceived(StatementContext, [Int])
        case describeInfoReceived(StatementContext, DescribeInfo)
        case streaming(
            StatementContext,
            DescribeInfo,
            OracleBackendMessage.RowHeader,
            RowStreamStateMachine
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

        case forwardRows([DataRow])
        case forwardStreamComplete([DataRow], cursorID: UInt16, affectedRows: Int)
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

        case .rowCountsReceived(let context, _), .describeInfoReceived(let context, _):
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

        case .streaming(_, let describeInfo, _, var streamStateMachine):
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
                        logger: context.logger,
                        batchErrors: nil,
                        rowCounts: nil
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

        case .initialized, .rowCountsReceived, .error, .commandComplete:
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
            let outBinds = context.binds.metadata.compactMap(\.outContainer)
            precondition(rowData.columns.count == outBinds.count)
            for (index, column) in rowData.columns.enumerated() {
                switch column {
                case .data(let buffer):
                    outBinds[index].storage.withLockedValue { $0 = buffer }
                case .duplicate:
                    preconditionFailure("duplicate columns cannot happen in out binds")
                }
            }
            return .wait

        case .streaming(let context, let describeInfo, let rowHeader, var demandStateMachine):
            var out = ByteBuffer()
            for column in rowData.columns {
                switch column {
                case .data(var buffer):
                    out.writeBuffer(&buffer)
                case .duplicate(let index):
                    var data = demandStateMachine.receivedDuplicate(at: index)
                    try! out.writeLengthPrefixed(as: UInt8.self) { buffer in
                        buffer.writeBuffer(&data)
                    }  // must work
                }
            }
            let row = DataRow(columnCount: describeInfo.columns.count, bytes: out)
            demandStateMachine.receivedRow(row)
            self.avoidingStateMachineCoWVoid { state in
                state = .streaming(
                    context, describeInfo, rowHeader, demandStateMachine
                )
            }
            return .wait

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

        case .drain:
            // This state might occur, if the client cancelled the statement,
            // but the server did not yet receive/process the cancellation
            // marker. Due to that it might send more data without knowing yet.
            return .wait

        default:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func queryParameterReceived(_ parameter: OracleBackendMessage.QueryParameter) -> Action {
        if let rowCounts = parameter.rowCounts {
            guard case .initialized(let statementContext) = state else {
                preconditionFailure("Invalid state: \(self.state)")
            }
            self.state = .modifying
            self.state = .rowCountsReceived(statementContext, rowCounts.map(Int.init))
        }
        return .wait
    }

    mutating func errorReceived(
        _ error: OracleBackendMessage.BackendError
    ) -> Action {
        let batchErrors = error.batchErrors.map(OracleSQLError.BatchError.init)

        let action: Action
        if Constants.TNS_ERR_NO_DATA_FOUND == error.number
            || Constants.TNS_ERR_ARRAY_DML_ERRORS == error.number
        {
            switch self.state {
            case .commandComplete, .error, .drain:
                return .wait  // stream has already finished

            case .initialized(let context),
                .describeInfoReceived(let context, _):
                if let cursorID = error.cursorID {
                    context.cursorID.store(cursorID, ordering: .relaxed)
                }

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
                        promise,
                        .init(
                            value: .noRows(affectedRows: Int(error.rowCount ?? 0)),
                            logger: context.logger,
                            batchErrors: batchErrors,
                            rowCounts: nil
                        )
                    )  // empty response
                }

            case .rowCountsReceived(let context, let rowCounts):
                if let cursorID = error.cursorID {
                    context.cursorID.store(cursorID, ordering: .relaxed)
                }

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
                        promise,
                        .init(
                            value: .noRows(affectedRows: Int(error.rowCount ?? 0)),
                            logger: context.logger,
                            batchErrors: batchErrors,
                            rowCounts: rowCounts
                        )
                    )  // empty response
                }

            case .streaming(let context, _, _, var demandStateMachine):
                if let cursorID = error.cursorID {
                    context.cursorID.store(cursorID, ordering: .relaxed)
                }

                self.avoidingStateMachineCoWVoid { state in
                    state = .commandComplete
                }

                let rows = demandStateMachine.end()
                action = .forwardStreamComplete(
                    rows, cursorID: context.cursorID.load(ordering: .relaxed), affectedRows: Int(error.rowCount ?? 0))

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
                context.cursorID.store(cursor, ordering: .relaxed)

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
                context.cursorID.store(cursor, ordering: .relaxed)

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
            case .drain:
                // This state might occur, if the client cancelled the
                // statement, but the server did not yet receive/process the
                // cancellation marker. Due to that it might send more data
                // without knowing yet.
                return .wait
            case .commandComplete, .error:
                preconditionFailure("This is impossible...")

            case .initialized(let context):
                if let cursorID = error.cursorID {
                    context.cursorID.store(cursorID, ordering: .relaxed)
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
                            value: .noRows(affectedRows: Int(error.rowCount ?? 0)),
                            logger: context.logger,
                            batchErrors: batchErrors,
                            rowCounts: nil
                        )
                    )
                }
                self.state = .commandComplete

            case .rowCountsReceived(let context, let rowCounts):
                if let cursorID = error.cursorID {
                    context.cursorID.store(cursorID, ordering: .relaxed)
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
                            value: .noRows(affectedRows: Int(error.rowCount ?? 0)),
                            logger: context.logger,
                            batchErrors: batchErrors,
                            rowCounts: rowCounts
                        )
                    )
                }
                self.state = .commandComplete

            case .describeInfoReceived(let context, let describeInfo):
                if let cursorID = error.cursorID {
                    context.cursorID.store(cursorID, ordering: .relaxed)
                }
                if describeInfo.columns.contains(where: {
                    [.clob, .nCLOB, .blob, .json, .vector].contains($0.dataType)
                }) {
                    context.requiresDefine.store(true, ordering: .relaxed)
                    context.noPrefetch.store(true, ordering: .relaxed)

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

            case .streaming(let statementContext, _, _, _):
                // no error actually happened, we need more rows
                if let cursorID = error.cursorID {
                    statementContext.cursorID.store(cursorID, ordering: .relaxed)
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

    mutating func ioVectorReceived(
        _ vector: OracleBackendMessage.InOutVector
    ) -> Action {
        switch self.state {
        case .initialized(let context):
            guard context.binds.count == vector.bindMetadata.count else {
                preconditionFailure(
                    """
                    mismatch in binds - sent: \(context.binds.count), \
                    received: \(vector.bindMetadata.count)
                    """)
            }

            // we won't change the state
            return .wait

        case .rowCountsReceived,
            .describeInfoReceived,
            .streaming,
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

        case .rowCountsReceived,
            .describeInfoReceived,
            .streaming,
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
            .rowCountsReceived(let context, _),
            .describeInfoReceived(let context, _),
            .streaming(let context, _, _, _):
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

        case .drain, .rowCountsReceived, .describeInfoReceived:
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
            .rowCountsReceived,
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
        case .initialized,
            .commandComplete,
            .drain,
            .error,
            .rowCountsReceived,
            .describeInfoReceived:
            // we already have the complete stream received, now we are waiting
            // for a `readyForStatement` package. To receive this we need to read.
            return .read

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    // MARK: Private Methods

    private mutating func setAndFireError(_ error: OracleSQLError) -> Action {
        switch self.state {
        case .initialized(let context),
            .rowCountsReceived(let context, _),
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

        case .streaming(_, _, _, var streamState):
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

    var isComplete: Bool {
        switch self.state {
        case .initialized,
            .rowCountsReceived,
            .describeInfoReceived,
            .streaming,
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
