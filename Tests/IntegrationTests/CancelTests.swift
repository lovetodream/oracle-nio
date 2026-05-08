//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import OracleNIO
import Testing

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// End-to-end tests for ``OracleConnection/cancel()`` against a live
/// Oracle Database. They cover the three statement substates the
/// cancel handshake has to handle:
///
/// 1. **Pre-streaming** (statement parsing / executing / blocked in
///    `dbms_session.sleep`) — TNS BREAK + RESET; promise fails with
///    `.statementCancelled`.
/// 2. **Mid-stream** (server is sending rows) — fail the row stream
///    locally + RESET; row iterator throws `.statementCancelled`.
/// 3. **Idle** — no statement in flight; cancel is a no-op.
///
/// Each test verifies both that the in-flight operation reports
/// `.statementCancelled` *and* that a follow-up `SELECT` runs
/// promptly (proving the connection isn't stuck waiting for the
/// orphan operation to finish).
@Suite(
    .disabled(if: env("SMOKE_TEST_ONLY") == "1", "running only smoke test suite"),
    .timeLimit(.minutes(2))
)
struct CancelTests {

    private let group: EventLoopGroup
    private var eventLoop: EventLoop { group.next() }

    init() {
        self.group = NIOSingletons.posixEventLoopGroup
    }

    /// Cancel during `dbms_session.sleep` — the canonical
    /// pre-streaming case. The server's kernel sleep checks for
    /// breaks at next opportunity, so the cancel→done window is
    /// "a few seconds" rather than instant; a strict instant
    /// assertion would be flaky here.
    @Test func cancelDuringKernelSleep() async throws {
        try await withOracleConnection(on: eventLoop) { conn in
            try await Self.runCancelCase(
                on: conn,
                sql: "BEGIN dbms_session.sleep(10); END;",
                cancelAfter: .seconds(1),
                expectedFollowUpUnderSeconds: 8  // sleep would naturally take ~9s remaining
            )
        }
    }

    /// Cancel a CPU-bound query while it's executing on the server
    /// (statement is in pre-streaming state, no rows produced yet).
    /// Should interrupt nearly instantly because the PL/SQL VM /
    /// SQL engine checks breaks at every fetch boundary.
    @Test func cancelDuringCPUBoundExecute() async throws {
        try await withOracleConnection(on: eventLoop) { conn in
            try await Self.runCancelCase(
                on: conn,
                sql: """
                    SELECT COUNT(*) FROM (
                        SELECT a.n + b.n + c.n AS x
                        FROM (SELECT ROWNUM n FROM dual CONNECT BY ROWNUM <= 1000) a,
                             (SELECT ROWNUM n FROM dual CONNECT BY ROWNUM <= 1000) b,
                             (SELECT ROWNUM n FROM dual CONNECT BY ROWNUM <= 1000) c
                        WHERE MOD(a.n + b.n + c.n, 7) = 1
                    )
                    """,
                cancelAfter: .milliseconds(500),
                expectedFollowUpUnderSeconds: 2
            )
        }
    }

    /// Cancel mid-fetch — the row stream is actively streaming
    /// rows when the cancel arrives. Hits the `.streaming` branch
    /// of ``ConnectionStateMachine/triggerBreak()`` (delegates to
    /// the existing iterator-drop path).
    @Test func cancelMidFetch() async throws {
        try await withOracleConnection(on: eventLoop) { conn in
            let cancelExpectation = ManagedAtomicBool(false)

            let runTask = Task.detached {
                let stream = try await conn.execute(
                    "SELECT level FROM dual CONNECT BY level <= 10000000",
                    logger: .oracleTest
                )
                do {
                    var rows = 0
                    for try await _ in stream {
                        rows += 1
                        if rows == 100 { cancelExpectation.value = true }
                    }
                    Issue.record("expected the row stream to be cancelled")
                } catch let error as OracleSQLError where error.code == .statementCancelled {
                    // expected
                } catch {
                    Issue.record("unexpected error: \(error)")
                }
            }

            // Wait until we've consumed at least 100 rows, then cancel.
            let deadline = Date().addingTimeInterval(5)
            while !cancelExpectation.value, Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(cancelExpectation.value, "row stream never started fetching")
            conn.cancel()
            try? await runTask.value

            // Connection should be reusable immediately.
            let t0 = Date()
            let stream = try await conn.execute("SELECT 1 FROM dual", logger: .oracleTest)
            for try await _ in stream {}
            #expect(Date().timeIntervalSince(t0) < 2)
        }
    }

    /// Cancel while idle is a no-op, and subsequent statements
    /// continue to work.
    @Test func cancelOnIdleConnection() async throws {
        try await withOracleConnection(on: eventLoop) { conn in
            conn.cancel()
            try? await Task.sleep(for: .milliseconds(50))
            let stream = try await conn.execute("SELECT 1 FROM dual", logger: .oracleTest)
            var count = 0
            for try await _ in stream { count += 1 }
            #expect(count == 1)
        }
    }

    /// Two cancels in quick succession on the same in-flight
    /// statement must not corrupt the connection — the second is
    /// idempotent and the connection is reusable afterwards.
    @Test func doubleCancelIsIdempotent() async throws {
        try await withOracleConnection(on: eventLoop) { conn in
            let runTask = Task.detached {
                do {
                    let stream = try await conn.execute(
                        "BEGIN dbms_session.sleep(10); END;",
                        logger: .oracleTest
                    )
                    for try await _ in stream {}
                    Issue.record("expected cancellation")
                } catch let error as OracleSQLError where error.code == .statementCancelled {
                    // expected
                } catch {
                    Issue.record("unexpected error: \(error)")
                }
            }

            try await Task.sleep(for: .milliseconds(500))
            conn.cancel()
            conn.cancel()  // second cancel — must be a no-op
            await runTask.value

            // Connection is reusable.
            let stream = try await conn.execute("SELECT 1 FROM dual", logger: .oracleTest)
            for try await _ in stream {}
        }
    }

    // MARK: - Helpers

    /// Run a cancel scenario: kick off `sql`, wait `cancelAfter`,
    /// call `conn.cancel()`, expect the in-flight task to throw
    /// `.statementCancelled`, then run a follow-up `SELECT 1` and
    /// require it to complete in under `expectedFollowUpUnderSeconds`.
    private static func runCancelCase(
        on conn: OracleConnection,
        sql: String,
        cancelAfter: Duration,
        expectedFollowUpUnderSeconds: Double
    ) async throws {
        let runTask = Task.detached {
            do {
                let stream = try await conn.execute(
                    OracleStatement(unsafeSQL: sql), logger: .oracleTest
                )
                for try await _ in stream {}
                Issue.record("expected cancellation, but SQL completed: \(sql)")
            } catch let error as OracleSQLError where error.code == .statementCancelled {
                // expected
            } catch {
                Issue.record("unexpected error from cancelled SQL: \(error)")
            }
        }

        try await Task.sleep(for: cancelAfter)
        let t0 = Date()
        conn.cancel()

        // Follow-up should run promptly once the server replies to
        // the BREAK/RESET handshake.
        let followUpStart = Date()
        let stream = try await conn.execute("SELECT 'ok' FROM dual", logger: .oracleTest)
        var sawRow = false
        for try await _ in stream { sawRow = true }
        #expect(sawRow, "follow-up SELECT returned no rows")
        let elapsed = Date().timeIntervalSince(followUpStart)
        #expect(
            elapsed < expectedFollowUpUnderSeconds,
            "follow-up SELECT took \(elapsed)s; expected < \(expectedFollowUpUnderSeconds)s"
        )

        await runTask.value
        _ = t0
    }
}

/// Lightweight `Sendable`-friendly atomic Bool used by the tests.
private final class ManagedAtomicBool: @unchecked Sendable {
    private let lock = NIOLock()
    private var _value: Bool

    init(_ initial: Bool) { _value = initial }

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
