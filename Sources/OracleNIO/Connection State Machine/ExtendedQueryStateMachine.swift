import NIOCore

struct ExtendedQueryStateMachine {

    private enum State {
        case initialized(ExtendedQueryContext)
        case describeInfoReceived(ExtendedQueryContext, DescribeInfo)
        case streaming(
            ExtendedQueryContext,
            DescribeInfo,
            OracleBackendMessage.RowHeader,
            RowStreamStateMachine
        )
        case streamingAndWaiting(
            ExtendedQueryContext,
            DescribeInfo,
            OracleBackendMessage.RowHeader,
            RowStreamStateMachine,
            partial: ByteBuffer
        )
        /// Indicates that the current query was cancelled and we want to drain rows from the
        /// connection ASAP.
        case drain([DescribeInfo.Column])

        case commandComplete
        case error(OracleSQLError)

        case modifying
    }

    enum Action {
        case sendExecute(ExtendedQueryContext, DescribeInfo?)
        case sendReexecute(ExtendedQueryContext, CleanupContext)
        case sendFetch(ExtendedQueryContext)

        case failQuery(EventLoopPromise<OracleRowStream>, with: OracleSQLError)
        case succeedQuery(EventLoopPromise<OracleRowStream>, QueryResult)

        case evaluateErrorAtConnectionLevel(OracleSQLError)

        case needMoreData

        case forwardRows([DataRow])
        case forwardStreamComplete([DataRow])
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

    init(queryContext: ExtendedQueryContext) {
        self.isCancelled = false
        self.state = .initialized(queryContext)
    }

    mutating func start() -> Action {
        guard case .initialized(let queryContext) = state else {
            preconditionFailure(
                "Start should only be called, if the query has been initialized"
            )
        }

        return .sendExecute(queryContext, nil)
    }

    mutating func cancel() -> Action {
        switch self.state {
        case .initialized:
            preconditionFailure(
                "Start must be called immediately after the query was created"
            )

        case .describeInfoReceived(let context, _):
            guard !self.isCancelled else {
                return .wait
            }

            self.isCancelled = true
            switch context.statement {
            case .ddl(let promise),
                .dml(let promise),
                .plsql(let promise),
                .query(let promise):
                return .failQuery(promise, with: .queryCancelled)
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
                    .queryCancelled, read: false, clientCancelled: true
                )
            case .read:
                return .forwardStreamError(
                    .queryCancelled, read: true, clientCancelled: true
                )
            }

        case .commandComplete, .error, .drain:
            // the stream has already finished
            return .wait

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    mutating func describeInfoReceived(_ describeInfo: DescribeInfo) -> Action {
        guard case .initialized(let context) = state else {
            preconditionFailure("Describe info should be the initial response")
        }

        self.avoidingStateMachineCoW { state in
            state = .describeInfoReceived(context, describeInfo)
        }

        return .wait
    }

    mutating func rowHeaderReceived(
        _ rowHeader: OracleBackendMessage.RowHeader
    ) -> Action {
        switch self.state {
        case .describeInfoReceived(let context, let describeInfo):
            self.avoidingStateMachineCoW { state in
                state = .streaming(context, describeInfo, rowHeader, .init())
            }

            switch context.statement {
            case .ddl(let promise),
                .dml(let promise),
                .plsql(let promise),
                .query(let promise):
                return .succeedQuery(
                    promise,
                    QueryResult(
                        value: .describeInfo(describeInfo.columns),
                        logger: context.logger
                    )
                )
            }

        case .streaming(
            let context, let describeInfo, let prevRowHeader, let streamState
        ):
            if prevRowHeader.bitVector == nil {
                self.avoidingStateMachineCoW { state in
                    state = .streaming(
                        context, describeInfo, rowHeader, streamState
                    )
                }
            }
            return .wait

        case .initialized, .streamingAndWaiting, .drain, .error, .commandComplete:
            preconditionFailure()

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    mutating func rowDataReceived(
        _ rowData: OracleBackendMessage.RowData,
        capabilities: Capabilities
    ) -> Action {
        switch self.state {
        case .initialized(let context):
            let outBinds = context.query.binds.metadata
                .compactMap(\.outContainer)
            guard !outBinds.isEmpty else { preconditionFailure() }
            var buffer = rowData.slice
            for outBind in outBinds {
                outBind.storage = ByteBuffer()
                let rowCount = buffer.readUB4() ?? 0
                guard rowCount > 0 else {
                    continue
                }
                
                do {
                    for _ in 0..<rowCount {
                        var columnData = try self.processColumnData(
                            from: &buffer,
                            oracleType: outBind.metadata.dataType._oracleType,
                            csfrm: outBind.metadata.dataType.csfrm,
                            bufferSize: outBind.metadata.bufferSize,
                            capabilities: capabilities
                        )

                        let actualBytesCount = buffer.readSB4() ?? 0
                        if actualBytesCount < 0 && 
                            outBind.metadata.dataType._oracleType == .boolean {
                            continue
                        } else if actualBytesCount != 0 && columnData != nil {
                            // TODO: throw this as error?
                            preconditionFailure("column truncated, length: \(actualBytesCount)")
                        }

                        guard columnData != nil else {
                            preconditionFailure("TODO: unhandled need more data")
                        }

                        outBind.storage!.writeBuffer(&columnData!)
                    }
                } catch {
                    guard let error = error as? OracleSQLError else {
                        preconditionFailure()
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

        default: preconditionFailure()
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
            self.avoidingStateMachineCoW { state in
                state = .streaming(
                    context, describeInfo, rowHeader, streamState
                )
            }
            return .wait

        default:
            preconditionFailure()
        }
    }

    mutating func errorReceived(
        _ error: OracleBackendMessage.BackendError
    ) -> Action {

        let action: Action
        if
            Constants.TNS_ERR_NO_DATA_FOUND == error.number ||
            Constants.TNS_ERR_ARRAY_DML_ERRORS == error.number
        {
            switch self.state {
            case .commandComplete, .error, .drain:
                preconditionFailure()
            case .initialized(let context), .describeInfoReceived(let context, _):
                self.avoidingStateMachineCoW { state in
                    state = .commandComplete
                }

                switch context.statement {
                case .query(let promise),
                     .plsql(let promise),
                     .dml(let promise),
                     .ddl(let promise):
                    action = .succeedQuery(
                        promise, .init(value: .noRows, logger: context.logger)
                    ) // empty response
                }

            case .streaming(_, _, _, var demandStateMachine),
                .streamingAndWaiting(_, _, _, var demandStateMachine, _):
                self.avoidingStateMachineCoW { state in
                    state = .commandComplete
                }

                let rows = demandStateMachine.end()
                action = .forwardStreamComplete(rows)

            case .modifying:
                preconditionFailure("invalid state")
            }
        } else if 
            error.number == Constants.TNS_ERR_VAR_NOT_IN_SELECT_LIST,
            let cursor = error.cursorID
        {
            switch self.state {
            case .initialized(let context):
                switch context.statement {
                case .query(let promise),
                    .plsql(let promise),
                    .dml(let promise),
                    .ddl(let promise):
                    action = .failQuery(promise, with: .server(error))
                }
            default:
                action = .forwardStreamError(
                    .server(error), read: false, cursorID: cursor
                )
            }

            self.avoidingStateMachineCoW { state in
                state = .error(.server(error))
            }
        } else if
            let cursor = error.cursorID,
            error.number != 0 && cursor != 0
        {
            let exception = getExceptionClass(for: Int32(error.number))
            switch self.state {
            case .initialized(let context):
                switch context.statement {
                case .query(let promise),
                    .plsql(let promise),
                    .dml(let promise),
                    .ddl(let promise):
                    action = .failQuery(promise, with: .server(error))
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

            self.avoidingStateMachineCoW { state in
                state = .error(.server(error))
            }
        } else if self.isCancelled && error.number == 1013 {
            self.state = .commandComplete
            action = .forwardCancelComplete
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
                switch context.statement {
                case .query(let promise),
                     .plsql(let promise),
                     .dml(let promise),
                     .ddl(let promise):
                    action = .succeedQuery(
                        promise, QueryResult(
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
                    [.clob, .nCLOB, .blob, .json].contains($0.dataType)
                }) {
                    context.requiresDefine = true
                    context.noPrefetch = true

                    if !context.options.fetchLOBs {
                        var describeInfo = describeInfo
                        self.avoidingStateMachineCoW { state in
                            describeInfo.columns = describeInfo.columns.map {
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
                                    col.bufferSize = col.dataTypeSize *
                                        UInt32(col.dataType.bufferSizeFactor)
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

                } else {
                    action = .sendFetch(context)
                }

            case .streaming(let extendedQueryContext, _, _, _),
                 .streamingAndWaiting(let extendedQueryContext, _, _, _, _):
                // no error actually happened, we need more rows
                if let cursorID = error.cursorID {
                    extendedQueryContext.cursorID = cursorID
                }
                action = .sendFetch(extendedQueryContext)

            case .modifying:
                preconditionFailure("invalid state")
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
            // Could happen if we cancelled the query while the database is
            // still sending stuff
            return .wait

        case .streamingAndWaiting(
            let extendedQueryContext,
            let describeInfo,
            let rowHeader,
            let streamState,
            var partial
        ):
            partial.writeImmutableBuffer(buffer)
            self.avoidingStateMachineCoW { state in
                state = .streaming(
                    extendedQueryContext, describeInfo, rowHeader, streamState
                )
            }
            return self.moreDataReceived(
                &partial,
                capabilities: capabilities,
                context: extendedQueryContext,
                describeInfo: describeInfo
            )

        default:
            preconditionFailure("invalid state: \(self.state)")
        }
    }

    mutating func ioVectorReceived(
        _ vector: OracleBackendMessage.InOutVector
    ) -> Action {
        switch self.state {
        case .initialized(let context):
            // TODO: Parse the vector and see if we have any out or inout binds 
            // we have to handle. It'll be added with the support for out binds.
            // For now we do not support out binds at all.

            if vector.bindMetadata.contains(where: {
                $0.direction != Constants.TNS_BIND_DIR_INPUT
            }) {
                // Let's log a warning here, so the user knows what's going on.
                context.logger.warning("""
                Received one or more IN/OUT or OUT variables from a PL/SQL \
                query. OUTPUT variables are not supported yet. Please refactor \
                your statements if possible.
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
            preconditionFailure("invalid state")
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
                "We can't send a fetch if the query completed already"
            )
        case .modifying:
            preconditionFailure("Invalid state")
        }
    }

    mutating func requestQueryRows() -> Action {
        switch self.state {
        case .streaming(
            let queryContext,
            let describeInfo,
            let rowHeader,
            var demandStateMachine
        ):
            return self.avoidingStateMachineCoW { state in
                let action = demandStateMachine.demandMoreResponseBodyParts()
                state = .streaming(
                    queryContext, describeInfo, rowHeader, demandStateMachine
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
            preconditionFailure("""
            The stream is already closed or in a failure state; \
            rows can not be consumed at this time.
            """)

        case .modifying:
            preconditionFailure("invalid state")
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
            preconditionFailure("invalid state")
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
            // for a `readyForQuery` package. To receive this we need to read.
            return .read

        case .modifying:
            preconditionFailure("invalid state")
        }
    }

    // MARK: Private Methods

    private mutating func moreDataReceived(
        _ buffer: inout ByteBuffer,
        capabilities: Capabilities,
        context: ExtendedQueryContext,
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
                let decodingContext = OracleBackendMessageDecoder.Context()
                decodingContext.queryOptions = context.options
                decodingContext.columnsCount = describeInfo?.columns.count
                let messages = try OracleBackendMessage.decode(
                    from: &slice,
                    of: .data,
                    capabilities: capabilities,
                    skipDataFlags: false,
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
                    default:
                        preconditionFailure()
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
            let context, let describeInfo, let rowHeader, var demandStateMachine
        ):
            let readerIndex = buffer.readerIndex
            do {
                switch try self.rowDataReceived(
                    buffer: &buffer,
                    describeInfo: describeInfo,
                    rowHeader: rowHeader,
                    capabilities: capabilities,
                    demandStateMachine: &demandStateMachine
                ) {
                case .row(let row):
                    demandStateMachine.receivedRow(row)
                    self.avoidingStateMachineCoW { state in
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

                    self.avoidingStateMachineCoW { state in
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
                    preconditionFailure()
                }
                return self.setAndFireError(error)
            }

        default:
            preconditionFailure()
        }

        return .wait
    }

    private mutating func setAndFireError(_ error: OracleSQLError) -> Action {
        switch self.state {
        case .initialized(let context), .describeInfoReceived(let context, _):
            if self.isCancelled {
                return .evaluateErrorAtConnectionLevel(error)
            } else {
                switch context.statement {
                case .ddl(let promise),
                    .dml(let promise),
                    .plsql(let promise),
                    .query(let promise):
                    self.state = .error(error)
                    return .failQuery(promise, with: error)
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
            preconditionFailure("""
            This state must not be reached. If the query `.isComplete`, the 
            ConnectionStateMachine must not send any further events to the
            substate machine.
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

    private func processColumnData(
        from buffer: inout ByteBuffer,
        oracleType: DataType.Value?,
        csfrm: UInt8,
        bufferSize: UInt32,
        capabilities: Capabilities
    ) throws -> ByteBuffer? {
        let columnValue: ByteBuffer
        if bufferSize == 0 && ![.long, .longRAW, .uRowID].contains(oracleType) {
            columnValue = ByteBuffer(bytes: [0]) // NULL indicator
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
            .binaryInteger, .boolean, .intervalDS, .cursor:
            switch buffer.readOracleSlice() {
            case .some(let slice):
                columnValue = slice
            case .none:
                return nil // need more data
            }
        case .clob, .blob:

            // LOB has a UB4 length indicator instead of the usual UInt8
            let length = try buffer.throwingReadUB4()
            if length > 0 {
                let size = try buffer.throwingReadUB8()
                let chunkSize = try buffer.throwingReadUB4()
                var locator = try buffer.readOracleSpecificLengthPrefixedSlice()
                var tempBuffer = ByteBuffer()
                tempBuffer.writeInteger(size)
                tempBuffer.writeInteger(chunkSize)
                tempBuffer.writeBuffer(&locator)
                var columnValue = ByteBuffer()
                tempBuffer.encode(into: &columnValue, context: .default)
                return columnValue
            } else {
                columnValue = .init(bytes: [0]) // empty buffer
            }
        case .json:
            // TODO: OSON
            // OSON has a UB4 length indicator instead of the usual UInt8
            fatalError("not implemented")
        default:
            fatalError("not implemented")
        }

        if [.long, .longRAW].contains(oracleType) {
            buffer.skipSB4() // null indicator
            buffer.skipUB4() // return code
        }

        return columnValue
    }

    private mutating func rowDataReceived(
        buffer: inout ByteBuffer,
        describeInfo: DescribeInfo,
        rowHeader: OracleBackendMessage.RowHeader,
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

extension ExtendedQueryStateMachine {
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
    ///
    /// Sadly, because it's generic and has a closure, we need to force it to be inlined at all call sites,
    /// which is not idea.
    @inline(__always)
    private mutating func avoidingStateMachineCoW<ReturnType>(
        _ body: (inout State) -> ReturnType
    ) -> ReturnType {
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
