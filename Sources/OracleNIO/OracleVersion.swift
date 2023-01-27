/// Oracle Release Number Format:
/// ```
/// 12.1.0.1.0
///  ┬ ┬ ┬ ┬ ┬
///  │ │ │ │ └───── Platform-Specific Release Number
///  │ │ │ └────────── Component-Specific Release Number
///  │ │ └─────────────── Fusion Middleware Release Number
///  │ └──────────────────── Database Maintenance Release Number
///  └───────────────────────── Major Database Release Number
///  ```
struct OracleVersion {
    let majorDatabaseReleaseNumber: Int
    let databaseMaintenanceReleaseNumber: Int
    let fusionMiddlewareReleaseNumber: Int
    let componentSpecificReleaseNumber: Int
    let platformSpecificReleaseNumber: Int

    func formatted() -> String {
        "\(majorDatabaseReleaseNumber)." +
        "\(databaseMaintenanceReleaseNumber)." +
        "\(fusionMiddlewareReleaseNumber)." +
        "\(componentSpecificReleaseNumber)." +
        "\(platformSpecificReleaseNumber)"
    }
}
