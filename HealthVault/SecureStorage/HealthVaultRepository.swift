//
//  HealthVaultRepository.swift
//  HealthVault
//
//  Repository for health metrics using the encrypted database.
//

import Foundation

struct HealthMetricRecord: Sendable {
    let id: Int64?
    let type: String
    let value: Double
    let unit: String?
    let startDate: Date
    let endDate: Date?
    let source: String?
    let createdAt: Date
}

extension HealthMetricRecord {
    static let typeSteps = "steps"
    static let typeSleepHours = "sleep_hours"
    static let typeHeartRate = "heart_rate"
}

final class HealthVaultRepository: Sendable {
    private let db: SecureDatabaseProtocol

    init(database: SecureDatabaseProtocol) {
        self.db = database
    }

    func insert(record: HealthMetricRecord) throws {
        try db.execute(
            """
            INSERT INTO health_metrics (type, value, unit, start_date, end_date, source, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            parameters: [
                record.type,
                record.value,
                record.unit ?? NSNull(),
                record.startDate.timeIntervalSince1970,
                record.endDate?.timeIntervalSince1970 ?? NSNull(),
                record.source ?? NSNull(),
                record.createdAt.timeIntervalSince1970
            ]
        )
    }

    func fetchMetrics(type: String? = nil, from start: Date, to end: Date) throws -> [HealthMetricRecord] {
        var sql = "SELECT * FROM health_metrics WHERE start_date >= ? AND (end_date IS NULL OR end_date <= ?)"
        var params: [Any] = [start.timeIntervalSince1970, end.timeIntervalSince1970]
        if let t = type {
            sql += " AND type = ?"
            params.append(t)
        }
        sql += " ORDER BY start_date ASC"
        let rows = try db.query(sql, parameters: params)
        return rows.compactMap { row in
            guard let type = row["type"] as? String,
                  let value = (row["value"] as? Double) ?? (row["value"] as? Int64).map(Double.init),
                  let startStamp = (row["start_date"] as? Double) ?? (row["start_date"] as? Int64).map(Double.init),
                  let createdStamp = (row["created_at"] as? Double) ?? (row["created_at"] as? Int64).map(Double.init) else { return nil }
            let endStamp = (row["end_date"] as? Double) ?? (row["end_date"] as? Int64).map(Double.init)
            return HealthMetricRecord(
                id: (row["id"] as? Int64) ?? (row["id"] as? Int).map(Int64.init),
                type: type,
                value: value,
                unit: row["unit"] as? String,
                startDate: Date(timeIntervalSince1970: startStamp),
                endDate: endStamp.map { Date(timeIntervalSince1970: $0) },
                source: row["source"] as? String,
                createdAt: Date(timeIntervalSince1970: createdStamp)
            )
        }
    }
}
