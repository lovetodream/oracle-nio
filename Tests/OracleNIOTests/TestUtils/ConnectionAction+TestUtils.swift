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

@testable import OracleNIO

extension ConnectionStateMachine {
    static func readyForStatement() -> Self {
        ConnectionStateMachine(.readyForStatement)
    }
}


// MARK: Equatable Conformance on ConnectionAction

#if compiler(>=6.0)
    extension ConnectionStateMachine.ConnectionAction: @retroactive Equatable {}
#else
    extension ConnectionStateMachine.ConnectionAction: Equatable {}
#endif
extension ConnectionStateMachine.ConnectionAction {
    public static func == (
        lhs: ConnectionStateMachine.ConnectionAction, rhs: ConnectionStateMachine.ConnectionAction
    ) -> Bool {
        switch (lhs, rhs) {
        case (.read, .read):
            return true
        case (.wait, .wait):
            return true
        case (.logoffConnection(let lhs), .logoffConnection(let rhs)):
            return lhs?.futureResult === rhs?.futureResult
        case (.closeConnection(let lhs), .closeConnection(let rhs)):
            return lhs?.futureResult === rhs?.futureResult
        case (.fireChannelInactive, .fireChannelInactive):
            return true
        case (.fireEventReadyForStatement, .fireEventReadyForStatement):
            return true

        case (.closeConnectionAndCleanup(let lhs), .closeConnectionAndCleanup(let rhs)):
            return lhs == rhs

        case (.sendConnect, .sendConnect):
            return true
        case (.sendProtocol, .sendProtocol):
            return true
        case (.sendDataTypes, .sendDataTypes):
            return true

        case (.provideAuthenticationContext, .provideAuthenticationContext):
            return true
        case (.sendFastAuth(let lhs), .sendFastAuth(let rhs)):
            return lhs == rhs
        case (
            .sendAuthenticationPhaseOne(let lhsContext), .sendAuthenticationPhaseOne(let rhsContext)
        ):
            return lhsContext == rhsContext
        case (
            .sendAuthenticationPhaseTwo(let lhsContext, let lhsParameters),
            .sendAuthenticationPhaseTwo(let rhsContext, let rhsParameters)
        ):
            return lhsContext == rhsContext && lhsParameters == rhsParameters
        case (.authenticated(let lhs), .authenticated(let rhs)):
            return lhs == rhs

        case (.sendPing, .sendPing):
            return true
        case (.failPing(let lhsPromise, let lhsError), .failPing(let rhsPromise, let rhsError)):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsError == rhsError
        case (.succeedPing(let lhs), .succeedPing(let rhs)):
            return lhs.futureResult === rhs.futureResult

        case (.sendCommit, .sendCommit):
            return true
        case (.failCommit(let lhsPromise, let lhsError), .failCommit(let rhsPromise, let rhsError)):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsError == rhsError
        case (.succeedCommit(let lhs), .succeedCommit(let rhs)):
            return lhs.futureResult === rhs.futureResult
        case (.sendRollback, .sendRollback):
            return true
        case (
            .failRollback(let lhsPromise, let lhsError), .failRollback(let rhsPromise, let rhsError)
        ):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsError == rhsError
        case (.succeedRollback(let lhs), .succeedRollback(let rhs)):
            return lhs.futureResult === rhs.futureResult

        case (.sendLOBOperation(let lhs), .sendLOBOperation(let rhs)):
            return lhs === rhs
        case (.succeedLOBOperation(let lhs), .succeedLOBOperation(let rhs)):
            return lhs === rhs
        case (
            .failLOBOperation(let lhsPromise, let lhsError),
            .failLOBOperation(let rhsPromise, let rhsError)
        ):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsError == rhsError

        case (.sendExecute(let lhsContext, let lhsInfo), .sendExecute(let rhsContext, let rhsInfo)):
            return lhsContext == rhsContext && lhsInfo == rhsInfo
        case (
            .sendReexecute(let lhsContext, let lhsCleanup),
            .sendReexecute(let rhsContext, let rhsCleanup)
        ):
            return lhsContext == rhsContext && lhsCleanup == rhsCleanup
        case (.sendFetch(let lhs), .sendFetch(let rhs)):
            return lhs == rhs
        case (.sendFlushOutBinds, .sendFlushOutBinds):
            return true
        case (
            .failStatement(let lhsPromise, let lhsError, let lhsCleanup),
            .failStatement(let rhsPromise, let rhsError, let rhsCleanup)
        ):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsError == rhsError
                && lhsCleanup == rhsCleanup
        case (
            .succeedStatement(let lhsPromise, let lhsResult),
            .succeedStatement(let rhsPromise, let rhsResult)
        ):
            return lhsPromise.futureResult === rhsPromise.futureResult
                && lhsResult.value == rhsResult.value
        case (.needMoreData, .needMoreData):
            return true

        case (.forwardRows(let lhs), .forwardRows(let rhs)):
            return lhs == rhs
        case (
            .forwardStreamComplete(let lhsRows, let lhsCursorID),
            .forwardStreamComplete(let rhsRows, let rhsCursorID)
        ):
            return lhsRows == rhsRows && lhsCursorID == rhsCursorID
        case (
            .forwardStreamError(let lhsError, let lhsRead, let lhsCursorID, let lhsClientCancelled),
            .forwardStreamError(let rhsError, let rhsRead, let rhsCursorID, let rhsClientCancelled)
        ):
            return lhsError == rhsError && lhsRead == rhsRead && lhsCursorID == rhsCursorID
                && lhsClientCancelled == rhsClientCancelled

        case (.sendMarker, .sendMarker):
            return true

        default:
            return false
        }
    }
}

#if compiler(>=6.0)
    extension ConnectionStateMachine.ConnectionAction.CleanUpContext: @retroactive Equatable {}
#else
    extension ConnectionStateMachine.ConnectionAction.CleanUpContext: Equatable {}
#endif
extension ConnectionStateMachine.ConnectionAction.CleanUpContext {
    public static func == (
        lhs: ConnectionStateMachine.ConnectionAction.CleanUpContext,
        rhs: ConnectionStateMachine.ConnectionAction.CleanUpContext
    ) -> Bool {
        lhs.action == rhs.action && lhs.tasks == rhs.tasks && lhs.error == rhs.error
            && lhs.closePromise?.futureResult === rhs.closePromise?.futureResult
    }
}

#if compiler(>=6.0)
    extension OracleSQLError: @retroactive Equatable {}
#else
    extension OracleSQLError: Equatable {}
#endif
extension OracleSQLError {
    public static func == (lhs: OracleSQLError, rhs: OracleSQLError) -> Bool {
        true
    }
}

#if compiler(>=6.0)
    extension OracleTask: @retroactive Equatable {}
#else
    extension OracleTask: Equatable {}
#endif
extension OracleTask {
    public static func == (lhs: OracleTask, rhs: OracleTask) -> Bool {
        switch (lhs, rhs) {
        case (.statement(let lhs), .statement(let rhs)):
            return lhs === rhs
        case (.ping, .ping):
            return true
        case (.commit, .commit):
            return true
        case (.rollback, .rollback):
            return true
        default:
            return false
        }
    }
}

#if compiler(>=6.0)
    extension CleanupContext: @retroactive Equatable {}
#else
    extension CleanupContext: Equatable {}
#endif
extension CleanupContext {
    public static func == (lhs: CleanupContext, rhs: CleanupContext) -> Bool {
        lhs.cursorsToClose == rhs.cursorsToClose && lhs.tempLOBsTotalSize == rhs.tempLOBsTotalSize
            && lhs.tempLOBsToClose == rhs.tempLOBsToClose
    }
}

#if compiler(>=6.0)
    extension StatementContext: @retroactive Equatable {}
#else
    extension StatementContext: Equatable {}
#endif
extension StatementContext {
    public static func == (lhs: StatementContext, rhs: StatementContext) -> Bool {
        lhs === rhs
    }
}

#if compiler(>=6.0)
    extension OracleRowStream: @retroactive Equatable {}
#else
    extension OracleRowStream: Equatable {}
#endif
extension OracleRowStream {
    public static func == (lhs: OracleRowStream, rhs: OracleRowStream) -> Bool {
        lhs === rhs
    }
}
