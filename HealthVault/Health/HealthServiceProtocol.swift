//
//  HealthServiceProtocol.swift
//  HealthVault
//
//  Abstraction for native health data. Implement with HealthKit on iOS
//  and Health Connect on Android for cross-platform apps.
//

import Foundation

struct HealthSample: Sendable {
    let type: HealthSampleType
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date?
    let sourceName: String?
}

enum HealthSampleType: String, Sendable {
    case steps
    case sleepHours
    case heartRate
}

/// Implement with HealthKit on iOS and Health Connect on Android.
protocol HealthServiceProtocol: Sendable {
    /// Check if health data is available and authorization can be requested.
    func isAvailable() async -> Bool

    /// Request read authorization for steps, sleep, heart rate.
    func requestAuthorization() async throws

    /// Fetch step count for the given date range.
    func fetchSteps(from start: Date, to end: Date) async throws -> [HealthSample]

    /// Fetch sleep analysis (hours) for the given date range.
    func fetchSleep(from start: Date, to end: Date) async throws -> [HealthSample]

    /// Fetch heart rate samples for the given date range.
    func fetchHeartRate(from start: Date, to end: Date) async throws -> [HealthSample]
}
