# OracleNIO

Non-blocking, event-driven Swift client for Oracle Databases built on [SwiftNIO](https://github.com/apple/swift-nio).

## Features

- An `OracleConnection` which allows you to connect to, authorize with, query, and retrieve results from an Oracle database server
- An async/await interface that supports backpressure
- Automatic conversions between Swift primitive types and the Oracle wire format
- Integrated with the Swift server ecosystem, including use of [swift-log](https://github.com/apple/swift-log).
- Designed to run efficiently on all supported platforms (tested on Linux and Darwin systems)
- Support for `Network.framework` when available (e.g. on Apple platforms)

OracleNIO does not provide a `ConnectionPool` as of today, but this is planned for a future release.

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
**Please be aware that the connection might fail due to TLS renegotiation not being supported at the moment**. 
Help is needed to implement this feature, see [#2](https://github.com/lovetodream/oracle-nio/issues/2).

## Getting started

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

### Querying

Once a connection is established, queries can be sent to the server. This is very straightforward:

```swift
let rows = try await connection.query("SELECT id, username, birthday FROM users", logger: logger)
```

> `query(_:logger:)` can run either a `Query`, `DML`, `DDL` or even `PlSQL`.

The query will return a `OracleRowSequence`, which is an `AsyncSequence` of `OracleRow`s. The rows can be iterated one-by-one:

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

- `Cursor` (partially implemented)
- `IntervalDS`
- `OracleNumber`
- `RowID`

### Querying with parameters

Sending parameterized queries to the database is also supported (in the coolest way possible):

```swift
let id = 1
let username = "fancyuser"
let birthday = Date()
try await connection.query("""
  INSERT INTO users (id, username, birthday) VALUES (\(id), \(username), \(birthday))
  """, 
  logger: logger
)
```

While this looks at first glance like a classic case of [SQL injection](https://en.wikipedia.org/wiki/SQL_injection) 😱, `OracleNIO`'s API ensures that this usage is safe. The first parameter of the `query(_:logger:)` method is not a plain `String`, but a `OracleQuery`, which implements Swift's `ExpressibleByStringInterpolation` protocol. `OracleNIO` uses the literal parts of the provided string as the SQL query and replaces each interpolated value with a parameter binding. Only values which implement the `OracleEncodable` protocol may be interpolated in this way. As with `OracleDecodable`, `OracleNIO` provides default implementations for most common types.

Some queries do not receive any rows from the server (most often `INSERT`, `UPDATE`, and `DELETE` queries, not to mention most `DDL` queries). To support this, the `query(_:logger:)` method is marked `@discardableResult`, so that the compiler does not issue a warning if the return value is not used.
