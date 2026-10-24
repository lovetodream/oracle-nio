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

import Benchmark
import Foundation
import NIOCore
import OracleMockServer
import OracleNIO

let port = env("ORA_MOCK_SERVER_PORT").flatMap(Int.init) ?? 6666

let config = OracleConnection.Configuration(
    host: "127.0.0.1",
    port: port,
    service: .serviceName("FREEPDB1"),
    username: "my_user",
    password: "my_passwor"
)

private func env(_ name: String) -> String? {
    getenv(name).flatMap { String(cString: $0) }
}

extension Benchmark {
    @discardableResult
    convenience init?(
        name: String,
        configuration: Benchmark.Configuration = Benchmark.defaultConfiguration,
        write: @escaping @Sendable (Benchmark, OracleConnection) async throws -> Void
    ) {
        var connection: OracleConnection!
        var server: Task<Void, Error>!
        self.init(name, configuration: configuration) { benchmark in
            for _ in benchmark.scaledIterations {
                for _ in 0..<25 {
                    try await write(benchmark, connection)
                }
            }
        } setup: {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                server = Task {
                    try await OracleMockServer.run(port: port, continuation: continuation)
                }
            }
            connection = try await OracleConnection.connect(
                configuration: config,
                id: 1
            )
        } teardown: {
            try await connection.close()
            server.cancel()
        }
    }
}

let benchmarks: @Sendable () -> Void = {
    var server: Task<Void, Error>!

    Benchmark.defaultConfiguration = .init(
        metrics: [
            .cpuTotal,
            .contextSwitches,
            .throughput,
            .mallocCountTotal,
        ],
        warmupIterations: 10
    )

    Benchmark(
        name: "SELECT:DUAL:1",
        configuration: .init(warmupIterations: 10)
    ) { _, connection in
        let stream = try await connection.execute("SELECT 'hello' FROM dual")
        for try await _ in stream.decode(String.self) {}  // consume stream
    }

    Benchmark(
        name: "SELECT:DUAL:10_000",
        configuration: .init(warmupIterations: 10)
    ) { _, connection in
        let stream = try await connection.execute(
            "SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')"
        )
        for try await _ in stream.decode(Int.self) {}  // consume stream
    }

    Benchmark(
        "CONNECT:DISCONNECT",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            let connection = try await OracleConnection.connect(
                configuration: config,
                id: 1
            )
            try await connection.close()
        }
    } setup: {
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            server = Task {
                try await OracleMockServer.run(port: port, continuation: continuation)
            }
        }
    } teardown: {
        server.cancel()
    }

    Benchmark(
        "ENCODING:STRING",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            var buffer = ByteBufferAllocator().buffer(capacity: 1024)
            while buffer.readableBytes < 1024 {
                "abcdefghijklmnopqrstuvwxyz"._encodeRaw(into: &buffer, context: .default)
            }
        }
    }

    let numberIntValues: [Int] = [0, 42, -42, 123_456_789, -987_654_321, .max, .min]
    let numberDoubleValues: [Double] = [0, 3.14, -3.14, 1234.5678, -0.000123, 1e20, -1e-20]

    Benchmark(
        "ENCODING:NUMBER:INT",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            var buffer = ByteBufferAllocator().buffer(capacity: 1024)
            while buffer.readableBytes < 1024 {
                for value in numberIntValues {
                    value.encode(into: &buffer, context: .default)
                }
            }
        }
    }

    Benchmark(
        "DECODING:NUMBER:INT",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        let templates: [ByteBuffer] = numberIntValues.map { value in
            var buffer = ByteBuffer()
            value.encode(into: &buffer, context: .default)
            return buffer
        }
        for _ in benchmark.scaledIterations {
            for template in templates {
                for _ in 0..<25 {
                    var buffer = template
                    _ = try Int(from: &buffer, type: .number, context: .default)
                }
            }
        }
    }

    // Exercises OracleNumeric.encodeNumeric's decimal-string path (used whenever a
    // fractional value is bound as a NUMBER via `OracleNumber`), as opposed to
    // BINARY_DOUBLE encoding below, which never goes through the digit-string format.
    Benchmark(
        "ENCODING:NUMBER:DOUBLE",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for value in numberDoubleValues {
                for _ in 0..<25 {
                    _ = OracleNumber(value)
                }
            }
        }
    }

    Benchmark(
        "DECODING:NUMBER:DOUBLE",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        let templates: [ByteBuffer] = numberDoubleValues.map { value in
            var buffer = ByteBuffer()
            OracleNumber(value).encode(into: &buffer, context: .default)
            return buffer
        }
        for _ in benchmark.scaledIterations {
            for template in templates {
                for _ in 0..<25 {
                    var buffer = template
                    _ = try Double(from: &buffer, type: .number, context: .default)
                }
            }
        }
    }

    Benchmark(
        "ENCODING:BINARY_DOUBLE",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            var buffer = ByteBufferAllocator().buffer(capacity: 1024)
            while buffer.readableBytes < 1024 {
                for value in numberDoubleValues {
                    value.encode(into: &buffer, context: .default)
                }
            }
        }
    }

    Benchmark(
        "DECODING:BINARY_DOUBLE",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        let templates: [ByteBuffer] = numberDoubleValues.map { value in
            var buffer = ByteBuffer()
            value.encode(into: &buffer, context: .default)
            return buffer
        }
        for _ in benchmark.scaledIterations {
            for template in templates {
                for _ in 0..<25 {
                    var buffer = template
                    _ = try Double(from: &buffer, type: .binaryDouble, context: .default)
                }
            }
        }
    }

    let dateValues: [Date] = [
        Date(timeIntervalSinceReferenceDate: 0),
        Date(timeIntervalSince1970: 0),
        Date(timeIntervalSinceReferenceDate: -63_82_400_000),  // long before the reference date
        Date(timeIntervalSinceReferenceDate: 63_82_400_000),  // long after the reference date
        Date(),  // now, exercises the fractional-seconds branch
    ]

    Benchmark(
        "ENCODING:DATE",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            var buffer = ByteBufferAllocator().buffer(capacity: 1024)
            while buffer.readableBytes < 1024 {
                for value in dateValues {
                    value.encode(into: &buffer, context: .default)
                }
            }
        }
    }

    Benchmark(
        "DECODING:DATE",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        let templates: [ByteBuffer] = dateValues.map { value in
            var buffer = ByteBuffer()
            value.encode(into: &buffer, context: .default)
            return buffer
        }
        for _ in benchmark.scaledIterations {
            for template in templates {
                for _ in 0..<25 {
                    var buffer = template
                    _ = try Date(from: &buffer, type: .timestampTZ, context: .default)
                }
            }
        }
    }

    struct BenchmarkJSONPayload: Codable {
        struct Nested: Codable {
            var a: Int
            var b: String
        }
        var id: Int
        var name: String
        var active: Bool
        var score: Double
        var tags: [String]
        var nested: Nested
    }

    let jsonTemplate: ByteBuffer = {
        var buffer = ByteBuffer()
        let payload = OracleJSON(
            BenchmarkJSONPayload(
                id: 42,
                name: "hello world",
                active: true,
                score: 3.14159,
                tags: ["a", "b", "c", "d"],
                nested: .init(a: 1, b: "nested string")
            )
        )
        try! payload.encode(into: &buffer, context: .default)
        return buffer
    }()

    Benchmark(
        "DECODING:JSON",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0..<25 {
                var buffer = jsonTemplate
                _ = try OracleJSON<BenchmarkJSONPayload>(
                    from: &buffer, type: .json, context: .default
                )
            }
        }
    }

    let vectorTemplate: ByteBuffer = {
        var buffer = ByteBuffer()
        let vector = OracleVectorFloat32((0..<256).map { Float32($0) })
        buffer.writeInteger(UInt8(0xDB))  // TNS_VECTOR_MAGIC_BYTE
        buffer.writeInteger(UInt8(0))  // TNS_VECTOR_VERSION_BASE
        buffer.writeInteger(UInt16(0x0012))  // TNS_VECTOR_FLAG_NORM_RESERVED | TNS_VECTOR_FLAG_NORM
        buffer.writeInteger(UInt8(2))  // VectorFormat.float32
        buffer.writeInteger(UInt32(vector.count))
        buffer.writeRepeatingByte(0, count: 8)
        vector.encode(into: &buffer, context: .default)
        return buffer
    }()

    Benchmark(
        "DECODING:VECTOR",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0..<25 {
                var buffer = vectorTemplate
                _ = try OracleVectorFloat32(
                    from: &buffer, type: .vector, context: .default
                )
            }
        }
    }

    // Builds a raw UB-encoded buffer by hand (length byte + value bytes)
    // rather than going through `writeUB4`/`writeUB8`, since those never
    // choose the 3-byte length encoding themselves.
    func ubBuffer(length: UInt8, _ writeValue: (inout ByteBuffer) -> Void) -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeInteger(length)
        writeValue(&buffer)
        return buffer
    }

    // One buffer holding many length bytes (high bit alternating), rewound between
    // passes, so the benchmark measures `readUBLength` itself rather than the
    // retain/release of copying a `ByteBuffer` for every call.
    let ubLengthCount = 8192
    let ubLengthTemplate: ByteBuffer = {
        var buffer = ByteBuffer()
        for index in 0..<ubLengthCount {
            buffer.writeInteger(index.isMultiple(of: 2) ? UInt8(0x02) : UInt8(0x82))
        }
        return buffer
    }()

    Benchmark(
        "DECODING:UBLENGTH",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        var buffer = ubLengthTemplate
        var sum: UInt = 0
        for _ in benchmark.scaledIterations {
            buffer.moveReaderIndex(to: 0)
            for _ in 0..<ubLengthCount {
                sum &+= UInt(buffer.readUBLength() ?? 0)
            }
        }
        blackHole(sum)
    }

    let ub4Templates: [ByteBuffer] = [
        ubBuffer(length: 0) { _ in },
        ubBuffer(length: 1) { $0.writeInteger(UInt8(0x7A)) },
        ubBuffer(length: 2) { $0.writeInteger(UInt16(0x1234)) },
        ubBuffer(length: 3) {
            $0.writeInteger(UInt16(0x1234))
            $0.writeInteger(UInt8(0x56))
        },
        ubBuffer(length: 4) { $0.writeInteger(UInt32(0x1234_5678)) },
    ]

    Benchmark(
        "DECODING:UB4",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0..<25 {
                for template in ub4Templates {
                    var buffer = template
                    _ = buffer.readUB4()
                }
            }
        }
    }

    let ub8Templates: [ByteBuffer] =
        ub4Templates + [
            ubBuffer(length: 8) { $0.writeInteger(UInt64(0x0102_0304_0506_0708)) }
        ]

    Benchmark(
        "DECODING:UB8",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0..<25 {
                for template in ub8Templates {
                    var buffer = template
                    _ = buffer.readUB8()
                }
            }
        }
    }

    let columnIsEmptyTemplates: [ByteBuffer] = [
        ByteBuffer(bytes: [0]),
        ByteBuffer(bytes: [Constants.TNS_NULL_LENGTH_INDICATOR]),
        ByteBuffer(bytes: [5]),
    ]

    // NVARCHAR2 columns use the national charset (csfrm 2), which is sent as
    // big-endian UTF-16 and takes a different decoding path than VARCHAR2.
    let utf16StringTemplate: ByteBuffer = {
        var buffer = ByteBuffer()
        let text = String(repeating: "Hello, Wörld! こんにちは 🌍 ", count: 20)
        for unit in text.utf16 {
            buffer.writeInteger(unit)
        }
        return buffer
    }()

    Benchmark(
        "DECODING:STRING:UTF16",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0..<25 {
                var buffer = utf16StringTemplate
                _ = try String(from: &buffer, type: .nVarchar, context: .default)
            }
        }
    }

    // Strings of different lengths cover the uint8 and uint16 length-prefix
    // branches of the JSON writer.
    struct BenchmarkJSONStringPayload: Codable {
        var short: [String]
        var medium: [String]
    }

    let jsonStringPayload = OracleJSON(
        BenchmarkJSONStringPayload(
            short: (0..<20).map { "short string \($0)" },
            medium: (0..<20).map { _ in String(repeating: "abcdefghij", count: 30) }
        )
    )

    Benchmark(
        "ENCODING:JSON:STRINGS",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0..<25 {
                var buffer = ByteBuffer()
                try jsonStringPayload.encode(into: &buffer, context: .default)
            }
        }
    }

    Benchmark(
        "DECODING:ORACLE_COLUMN_IS_EMPTY",
        configuration: .init(warmupIterations: 10)
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0..<25 {
                for template in columnIsEmptyTemplates {
                    _ = template.oracleColumnIsEmpty
                }
            }
        }
    }
}
