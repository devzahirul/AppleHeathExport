//
//  HealthKitService.swift
//  HealthVault
//
//  Fetches steps, sleep, and heart rate from Apple HealthKit.
//  Add the HealthKit capability in Signing & Capabilities and ensure
//  NSHealthShareUsageDescription / NSHealthUpdateUsageDescription are in Info.plist.
//

import Foundation
import HealthKit

final class HealthKitService: HealthServiceProtocol, @unchecked Sendable {
    private let store = HKHealthStore()

    func isAvailable() async -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        try await store.requestAuthorization(toShare: [], read: typesToRead)
    }

    func fetchSteps(from start: Date, to end: Date) async throws -> [HealthSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.typeNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (samples as? [HKQuantitySample])?.map { sample in
                    HealthSample(
                        type: .steps,
                        value: sample.quantity.doubleValue(for: .count()),
                        unit: "count",
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sourceName: sample.sourceRevision.source.name
                    )
                } ?? []
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }

    func fetchSleep(from start: Date, to end: Date) async throws -> [HealthSample] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.typeNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                // Map sleep analysis to hours (in bed + asleep)
                let asHours: [HealthSample] = categorySamples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue
                    }
                    .map { sample in
                        let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                        return HealthSample(
                            type: .sleepHours,
                            value: hours,
                            unit: "hr",
                            startDate: sample.startDate,
                            endDate: sample.endDate,
                            sourceName: sample.sourceRevision.source.name
                        )
                    }
                continuation.resume(returning: asHours)
            }
            store.execute(query)
        }
    }

    func fetchHeartRate(from start: Date, to end: Date) async throws -> [HealthSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.typeNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (samples as? [HKQuantitySample])?.map { sample in
                    HealthSample(
                        type: .heartRate,
                        value: sample.quantity.doubleValue(for: HKUnit(from: "count/min")),
                        unit: "count/min",
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sourceName: sample.sourceRevision.source.name
                    )
                } ?? []
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }
}

enum HealthKitError: Error {
    case notAvailable
    case typeNotAvailable
}
