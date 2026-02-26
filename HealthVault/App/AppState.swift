//
//  AppState.swift
//  HealthVault
//
//  Holds secure database, repository, health service; manages lock/unlock on biometric and background.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    /// Number of samples from Apple Watch in the last sync (0 if none or not synced yet).
    @Published var lastSyncFromWatchCount: Int = 0

    private(set) var secureDatabase: SecureDatabase?
    private(set) var repository: HealthVaultRepository?
    private(set) var healthService: HealthKitService?
    private(set) var exportService: ZeroKnowledgeExportService?

    init() {
        do {
            let db = try SecureDatabase()
            try db.lock()
            secureDatabase = db
            repository = HealthVaultRepository(database: db)
            healthService = HealthKitService()
            if let repo = repository {
                exportService = ZeroKnowledgeExportService(repository: repo)
            } else {
                exportService = nil
            }
        } catch {
            secureDatabase = nil
            repository = nil
            healthService = nil
            exportService = nil
        }
    }

    func unlock() {
        do {
            try secureDatabase?.unlock()
            isUnlocked = true
        } catch {
            syncError = error.localizedDescription
        }
    }

    func lock() {
        do {
            try secureDatabase?.lock()
            isUnlocked = false
        } catch {
            syncError = error.localizedDescription
        }
    }

    func persistAndLock() {
        do {
            try secureDatabase?.encryptAndPersist()
            try secureDatabase?.lock()
            isUnlocked = false
        } catch {
            syncError = error.localizedDescription
        }
    }

    func syncFromHealth() async {
        guard let health = healthService, let repo = repository, isUnlocked else { return }
        do {
            try await health.requestAuthorization()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
            let steps = try await health.fetchSteps(from: start, to: end)
            let sleep = try await health.fetchSleep(from: start, to: end)
            let heartRate = try await health.fetchHeartRate(from: start, to: end)
            var fromWatchCount = 0
            for s in steps {
                if isFromAppleWatch(s.sourceName) { fromWatchCount += 1 }
                try repo.insert(record: HealthMetricRecord(
                    id: nil,
                    type: HealthMetricRecord.typeSteps,
                    value: s.value,
                    unit: s.unit,
                    startDate: s.startDate,
                    endDate: s.endDate,
                    source: s.sourceName,
                    createdAt: Date()
                ))
            }
            for s in sleep {
                if isFromAppleWatch(s.sourceName) { fromWatchCount += 1 }
                try repo.insert(record: HealthMetricRecord(
                    id: nil,
                    type: HealthMetricRecord.typeSleepHours,
                    value: s.value,
                    unit: s.unit,
                    startDate: s.startDate,
                    endDate: s.endDate,
                    source: s.sourceName,
                    createdAt: Date()
                ))
            }
            for s in heartRate {
                if isFromAppleWatch(s.sourceName) { fromWatchCount += 1 }
                try repo.insert(record: HealthMetricRecord(
                    id: nil,
                    type: HealthMetricRecord.typeHeartRate,
                    value: s.value,
                    unit: s.unit,
                    startDate: s.startDate,
                    endDate: s.endDate,
                    source: s.sourceName,
                    createdAt: Date()
                ))
            }
            await MainActor.run {
                lastSyncDate = Date()
                lastSyncFromWatchCount = fromWatchCount
                syncError = nil
            }
        } catch {
            await MainActor.run {
                syncError = error.localizedDescription
            }
        }
    }

    private func isFromAppleWatch(_ sourceName: String?) -> Bool {
        guard let name = sourceName else { return false }
        return name.localizedCaseInsensitiveContains("Apple Watch")
    }
}
