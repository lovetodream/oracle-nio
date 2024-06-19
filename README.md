# OracleNIO

[![Supported Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flovetodream%2Foracle-nio%2Fbadge%3Ftype%3Dswift-versions)][SPI]
[![Supported Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flovetodream%2Foracle-nio%2Fbadge%3Ftype%3Dplatforms)][SPI]
[![SSWG Sandbox Incubating Badge](https://img.shields.io/badge/sswg-sandbox-lightgrey.svg)][SSWG Incubation]
[![Documentation](http://img.shields.io/badge/read_the-docs-2196f3.svg)][Documentation]
[![Apache 2.0 License](https://img.shields.io/badge/license-Apache%202.0-brightgreen)][Apache License]
[![codecov](https://codecov.io/gh/lovetodream/oracle-nio/graph/badge.svg?token=QIO79P61YM)][Coverage]
[![CI 23ai](https://github.com/lovetodream/oracle-nio/actions/workflows/test-23ai.yml/badge.svg)][Test 23ai]
[![CI 21c](https://github.com/lovetodream/oracle-nio/actions/workflows/test-21c.yml/badge.svg)][Test 21c]
[![CI ADB](https://github.com/lovetodream/oracle-nio/actions/workflows/test-adb.yml/badge.svg)][Test ADB]



Non-blocking, event-driven Swift client for Oracle Databases built on [SwiftNIO](https://github.com/apple/swift-nio).

It's like [PostgresNIO](https://github.com/vapor/postgres-nio), but written for Oracle Databases.

## Features

- An `OracleConnection` which allows you to connect to, authorize with, query, and retrieve results from an Oracle database server
- An async/await interface that supports backpressure
- Automatic conversions between Swift primitive types and the Oracle wire format
- Integrated with the Swift server ecosystem, including use of [swift-log](https://github.com/apple/swift-log).
- Designed to run efficiently on all supported platforms (tested on Linux and Darwin systems)
- Support for `Network.framework` when available (e.g. on Apple platforms)
- An `OracleClient` ConnectionPool backed by DRCP (Database Resident Connection Pooling) if available

## Supported Oracle Database versions

Oracle Database 12.1 or later.

## Connection methods

- Username and password with service name
- Username and password with sid
- Oracle Cloud Infrastructure (OCI) Identity and Access Management (IAM) token based authentication with service name
- Open Authorization (OAuth 2.0) token based authentication with service name
- Open Authorization (OAuth 2.0) token based authentication with sid

> Please note that all token based authentication methods are currently untested, because I (@lovetodream) do not have the infrastructure to test this. Contributions are welcome!

All connections can be TLS encrypted using `OracleConnection.Configuration.TLS`.

## API Docs

Check out the [OracleNIO API docs](https://swiftpackageindex.com/lovetodream/oracle-nio/documentation/oraclenio) for a detailed look at all of the classes, structs, protocols, and more.

## Getting started

### Adding the dependency

Add `OracleNIO` as a dependency to your `Package.swift`:

```swift
    dependencies: [
        .package(url: "https://github.com/lovetodream/oracle-nio.git", from: "1.0.0-alpha"),
        ...
    ]
```

Add `OracleNIO` to the target you want to use it in:

```swift
    targets: [
        .target(name: "MyFancyTarget", dependencies: [
            .product(name: "OracleNIO", package: "oracle-nio"),
        ])
    ]
```

### Creating a connection

To create a connection, first create a connection configuration object:

```swift
import OracleNIO

let config = OracleConnection.Configuration(
    host: "127.0.0.1", 
    port: 1521,
    service: .serviceName("my_service"), // or .sid("sid")
    username: "my_username",
    password: "my_password"
)
```

To create a connection we need a [`Logger`](https://apple.github.io/swift-log/docs/current/Logging/Structs/Logger.html), that is used to log connection background events.

```swift
import Logging

let logger = Logger(label: "oracle-logger")
```

Now we can put it together:

```swift
import OracleNIO
import Logging

let logger = Logger(label: "oracle-logger")

let config = OracleConnection.Configuration(
    host: "127.0.0.1", 
    port: 1521,
    service: .serviceName("my_service"),
    username: "my_username",
    password: "my_password"
)

let connection = try await OracleConnection.connect(
  configuration: config,
  id: 1,
  logger: logger
)

// Close your connection once done
try await connection.close()
```

### Running SQL statements

Once a connection is established, statements can be sent to the server. This is very straightforward:

```swift
let rows = try await connection.execute("SELECT id, username, birthday FROM users", logger: logger)
```

> `execute(_:options:logger:file:line:)` can run either a `Query`, `DML`, `DDL` or even `PlSQL`.

The statement will return a `OracleRowSequence`, which is an `AsyncSequence` of `OracleRow`s. The rows can be iterated one-by-one:

```swift
for try await row in rows {
  // do something with the row
}
```

### Decoding from OracleRow

However, in most cases it is much easier to request a row's fields as a set of Swift types:

```swift
for try await (id, username, birthday) in rows.decode((Int, String, Date).self) {
  // do something with the datatypes.
}
```

A type must implement the `OracleDecodable` protocol in order to be decoded from a row. `OracleNIO` provides default implementations for most of Swift's builtin types, as well as some types provided by Foundation:

- `Bool`
- `Bytes`, `ByteBuffer`, `Data`
- `Date`
- `UInt8`, `Int8`, `UInt16`, `Int16`, `UInt32`, `Int32`, `UInt64`, `Int64`, `UInt`, `Int`
- `Float`, `Double`
- `String`
- `UUID`

`OracleNIO` does provide some types which are more specific to Oracle too.

- `Cursor`
- `IntervalDS`
- `OracleNumber`
- `OracleVectorInt8`, `OracleVectorFloat32`, `OracleVectorFloat64`
- `RowID`

### Statements with parameters

Sending parameterized queries to the database is also supported (in the coolest way possible):

```swift
let id = 1
let username = "fancyuser"
let birthday = Date()
try await connection.execute("""
  INSERT INTO users (id, username, birthday) VALUES (\(id), \(username), \(birthday))
  """, 
  logger: logger
)
```

While this looks at first glance like a classic case of [SQL injection](https://en.wikipedia.org/wiki/SQL_injection) 😱, `OracleNIO`'s API ensures that this usage is safe. The first parameter of the `execute(_:options:logger:file:line:)` method is not a plain `String`, but a `OracleStatement`, which implements Swift's `ExpressibleByStringInterpolation` protocol. `OracleNIO` uses the literal parts of the provided string as the SQL statement and replaces each interpolated value with a parameter binding. Only values which implement the `OracleEncodable` protocol may be interpolated in this way. As with `OracleDecodable`, `OracleNIO` provides default implementations for most common types.

Some queries do not receive any rows from the server (most often `INSERT`, `UPDATE`, and `DELETE` queries, not to mention most `DDL` queries). To support this, the `execute(_:options:logger:file:line:)` method is marked `@discardableResult`, so that the compiler does not issue a warning if the return value is not used.

## Changelog

[SemVer](https://semver.org/) changes are documented for each release on the [releases page][Releases].

## Swift on Server Ecosystem

**Oracle NIO** is part of the [Swift on Server Working Group][SSWG] ecosystem - currently recommended as [**Sandbox Maturity**][SSWG Incubation].

| Proposal | Pitch | Review | Vote |
|:---:|:---:|:---:|:---:|
| [SSWG-0028](https://github.com/swift-server/sswg/blob/main/proposals/0028-oracle-nio.md) | [2023-12-20](https://forums.swift.org/t/pitch-oraclenio-oracle-db-driver-built-on-swiftnio/69088) | [2024-01-17](https://forums.swift.org/t/sswg-0028-oracle-nio/69502) | [2024-04-07](https://forums.swift.org/t/sswg-0028-oracle-nio/69502/6) |

## Language and Platform Support

Any given release of **Oracle NIO** will support at least the latest version of Swift on a given platform plus **1** previous version, at the time of the release.

Major version releases will be scheduled around official Swift releases, taking no longer **3 months** from the Swift release.

Major version releases will drop support for any version of Swift older than the last **2** Swift versions.

This policy is to balance the desire for as much backwards compatibility as possible, while also being able to take advantage of new Swift features for the best API design possible.

## License

[Apache 2.0][Apache License]

Copyright (c) 2023-present, Timo Zacherl (@lovetodream)

_This project contains code written by others not affliated with this project. All copyright claims are reserved by them. For a full list, with their claimed rights, see [NOTICE.txt](NOTICE.txt)_

_**Oracle** is a registered trademark of **Oracle Corporation**. Any use of their trademark is under the established [trademark guidelines](https://www.oracle.com/legal/trademarks.html) and does not imply any affiliation with or endorsement by them, and all rights are reserved by them._

_**Swift** is a registered trademark of **Apple, Inc**. Any use of their trademark does not imply any affiliation with or endorsement by them, and all rights are reserved by them._

[SSWG Incubation]: https://www.swift.org/sswg/incubation-process.html
[SSWG]: https://www.swift.org/sswg/
[SPI]: https://swiftpackageindex.com/lovetodream/oracle-nio
[Documentation]: https://swiftpackageindex.com/lovetodream/oracle-nio/documentation
[Apache License]: LICENSE
[Releases]: https://github.com/lovetodream/oracle-nio/releases
[Test 23ai]: https://github.com/lovetodream/oracle-nio/actions/workflows/test-23ai.yml
[Test 21c]: https://github.com/lovetodream/oracle-nio/actions/workflows/test-21c.yml
[Test ADB]: https://github.com/lovetodream/oracle-nio/actions/workflows/test-adb.yml
[Coverage]: https://codecov.io/gh/lovetodream/oracle-nio
