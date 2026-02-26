# Health Connect (Android) – Implementation Notes

This app is iOS-only. For an Android version, implement `HealthServiceProtocol` using **Health Connect**:

- **Steps**: `DataType.STEPS` (aggregate)
- **Sleep**: `DataType.SLEEP_SESSION` or sleep stages
- **Heart rate**: `DataType.HEART_RATE_BPM`

Use `HealthConnectClient` and the appropriate `ReadRequest` / `ReadRecordsRequest` with date ranges. Request permissions with `Permission.getReadPermission(type)` and `healthConnectClient.requestPermissions()`. Map Android record types to `HealthSample` (type, value, unit, startDate, endDate, sourceName).

No Swift code here; the Android app would implement the same protocol in Kotlin/Java and inject the service where `HealthKitService` is used on iOS.
