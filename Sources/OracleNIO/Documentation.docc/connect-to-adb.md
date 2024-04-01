# Connecting to Oracle Autonomous Databases

Examples showing a connection string and its corresponding ``OracleConnection/Configuration`` objects.

## Without a Wallet (TLS)

| TNS name | Connection string |
|---|---|
| name_low | (description= (retry_count=20)(retry_delay=3)(address=(protocol=tcps)(port=1521)(host=adb.eu-frankfurt-1.oraclecloud.com))(connect_data=(service_name=my_service_name_low.adb.oraclecloud.com))(security=(ssl_server_dn_match=yes))) |

```swift
let config = try OracleConnection.Configuration(
    host: "adb.eu-frankfurt-1.oraclecloud.com",
    port: 1521,
    service: .serviceName("my_service_name_low.adb.oraclecloud.com"),
    username: "my_username",
    password: "my_secure_password",
    tls: .require(.init(configuration: .clientDefault)) // indicates use of TLS
)

let connection = try await OracleConnection.connect(configuration: config, id: 1)

// start using your connection...

try await connection.close()
```

## With a Wallet (mTLS)

| TNS name | Connection string |
|---|---|
| name_low | (description= (retry_count=20)(retry_delay=3)(address=(protocol=tcps)(port=1522)(host=adb.eu-frankfurt-1.oraclecloud.com))(connect_data=(service_name=my_service_name_low.adb.oraclecloud.com))(security=(ssl_server_dn_match=yes))) |

```swift
let config = try OracleConnection.Configuration(
    host: "adb.eu-frankfurt-1.oraclecloud.com",
    port: 1521,
    service: .serviceName("my_service_name_low.adb.oraclecloud.com"),
    username: "my_username",
    password: "my_secure_password",
    tls: .require(.init(configuration: .makeOracleWalletConfiguration(
        wallet: "/path/to/Wallet_xxxx",
        walletPassword: "wallet_password"
    )))
)

let connection = try await OracleConnection.connect(configuration: config, id: 1)

// start using your connection...

try await connection.close()
```

### Related

``NIOSSL/TLSConfiguration/makeOracleWalletConfiguration(wallet:walletPassword:)``
