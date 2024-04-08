// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

@testable import OracleNIO

extension ConnectionStateMachine {
    static func readyForQuery() -> Self {
        ConnectionStateMachine(.readyForQuery)
    }
}


// MARK: Equatable Conformance on ConnectionAction

extension ConnectionStateMachine.ConnectionAction: Equatable {
    public static func == (lhs: ConnectionStateMachine.ConnectionAction, rhs: ConnectionStateMachine.ConnectionAction) -> Bool {
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
        case (.fireEventReadyForQuery, .fireEventReadyForQuery):
            return true

        case (.closeConnectionAndCleanup(let lhs), .closeConnectionAndCleanup(let rhs)):
            return lhs == rhs

        case (.sendConnect, .sendConnect):
            return true
        case (.sendProtocol, .sendProtocol):
            return true
        case (.sendDataTypes, .sendDataTypes):
            return true

        case (.provideAuthenticationContext(let lhs), .provideAuthenticationContext(let rhs)):
            return lhs == rhs
        case (.sendAuthenticationPhaseOne(let lhsContext, let lhsCookie), .sendAuthenticationPhaseOne(let rhsContext, let rhsCookie)):
            return lhsContext == rhsContext && lhsCookie == rhsCookie
        case (.sendAuthenticationPhaseTwo(let lhsContext, let lhsParameters), .sendAuthenticationPhaseTwo(let rhsContext, let rhsParameters)):
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
        case (.failRollback(let lhsPromise, let lhsError), .failRollback(let rhsPromise, let rhsError)):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsError == rhsError
        case (.succeedRollback(let lhs), .succeedRollback(let rhs)):
            return lhs.futureResult === rhs.futureResult

        case (.sendExecute(let lhsContext, let lhsInfo), .sendExecute(let rhsContext, let rhsInfo)):
            return lhsContext == rhsContext && lhsInfo == rhsInfo
        case (.sendReexecute(let lhsContext, let lhsCleanup), .sendReexecute(let rhsContext, let rhsCleanup)):
            return lhsContext == rhsContext && lhsCleanup == rhsCleanup
        case (.sendFetch(let lhs), .sendFetch(let rhs)):
            return lhs == rhs
        case (.sendFlushOutBinds, .sendFlushOutBinds):
            return true
        case (.failQuery(let lhsPromise, let lhsError, let lhsCleanup), .failQuery(let rhsPromise, let rhsError, let rhsCleanup)):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsError == rhsError && lhsCleanup == rhsCleanup
        case (.succeedQuery(let lhsPromise, let lhsResult), .succeedQuery(let rhsPromise, let rhsResult)):
            return lhsPromise.futureResult === rhsPromise.futureResult && lhsResult.value == rhsResult.value
        case (.needMoreData, .needMoreData):
            return true

        case (.forwardRows(let lhs), .forwardRows(let rhs)):
            return lhs == rhs
        case (.forwardStreamComplete(let lhsRows, let lhsCursorID), .forwardStreamComplete(let rhsRows, let rhsCursorID)):
            return lhsRows == rhsRows && lhsCursorID == rhsCursorID
        case (.forwardStreamError(let lhsError, let lhsRead, let lhsCursorID, let lhsClientCancelled), .forwardStreamError(let rhsError, let rhsRead, let rhsCursorID, let rhsClientCancelled)):
            return lhsError == rhsError &&
            lhsRead == rhsRead &&
            lhsCursorID == rhsCursorID &&
            lhsClientCancelled == rhsClientCancelled

        case (.sendMarker, .sendMarker):
            return true

        default:
            return false
        }
    }
}

extension ConnectionStateMachine.ConnectionAction.CleanUpContext: Equatable {
    public static func == (lhs: ConnectionStateMachine.ConnectionAction.CleanUpContext, rhs: ConnectionStateMachine.ConnectionAction.CleanUpContext) -> Bool {
        lhs.action == rhs.action && lhs.tasks == rhs.tasks && lhs.error == rhs.error && lhs.closePromise?.futureResult === rhs.closePromise?.futureResult
    }
}

extension OracleSQLError: Equatable {
    public static func == (lhs: OracleSQLError, rhs: OracleSQLError) -> Bool {
        true
    }
}

extension OracleTask: Equatable {
    public static func == (lhs: OracleTask, rhs: OracleTask) -> Bool {
        switch (lhs, rhs) {
        case (.extendedQuery(let lhs), .extendedQuery(let rhs)):
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

extension CleanupContext: Equatable {
    public static func == (lhs: CleanupContext, rhs: CleanupContext) -> Bool {
        lhs.cursorsToClose == rhs.cursorsToClose &&
        lhs.tempLOBsTotalSize == rhs.tempLOBsTotalSize &&
        lhs.tempLOBsToClose == rhs.tempLOBsToClose
    }
}

extension ExtendedQueryContext: Equatable {
    public static func == (lhs: ExtendedQueryContext, rhs: ExtendedQueryContext) -> Bool {
        lhs === rhs
    }
}

extension OracleRowStream: Equatable {
    public static func == (lhs: OracleRowStream, rhs: OracleRowStream) -> Bool {
        lhs === rhs
    }
}
