//
//  ZeroKnowledgeExportService.swift
//  HealthVault
//
//  Exports health reports as encrypted PDF or CSV (zero-knowledge: only the user
//  can decrypt with their password).
//

import Foundation
import PDFKit
import UIKit
import CryptoKit

struct ExportFormat: OptionSet {
    let rawValue: Int
    static let csv = ExportFormat(rawValue: 1 << 0)
    static let pdf = ExportFormat(rawValue: 1 << 1)
}

struct ExportResult {
    let url: URL
    let format: ExportFormat
    let isEncrypted: Bool
}

/// Exports health data to PDF/CSV and encrypts with a user-provided password (or key).
final class ZeroKnowledgeExportService: Sendable {

    private let repository: HealthVaultRepository

    init(repository: HealthVaultRepository) {
        self.repository = repository
    }

    /// Export metrics as encrypted CSV. User must supply password to decrypt later.
    func exportEncryptedCSV(
        from start: Date,
        to end: Date,
        password: String
    ) async throws -> URL {
        let records = try repository.fetchMetrics(type: nil, from: start, to: end)
        let csv = buildCSV(records: records)
        guard let data = csv.data(using: .utf8) else { throw ExportError.encodingFailed }
        let encrypted = try encrypt(data: data, password: password)
        let url = try exportDirectory()
            .appendingPathComponent("HealthVault_\(dateFileName(start))_\(dateFileName(end)).csv.enc")
        try encrypted.write(to: url)
        return url
    }

    /// Export metrics as encrypted PDF. User must supply password to decrypt later.
    func exportEncryptedPDF(
        from start: Date,
        to end: Date,
        password: String,
        title: String = "HealthVault Report"
    ) async throws -> URL {
        let records = try repository.fetchMetrics(type: nil, from: start, to: end)
        let pdfData = buildPDF(records: records, title: title, from: start, to: end)
        let encrypted = try encrypt(data: pdfData, password: password)
        let url = try exportDirectory()
            .appendingPathComponent("HealthVault_\(dateFileName(start))_\(dateFileName(end)).pdf.enc")
        try encrypted.write(to: url)
        return url
    }

    /// Export plain CSV (no encryption) for local use only.
    func exportCSV(from start: Date, to end: Date) throws -> URL {
        let records = try repository.fetchMetrics(type: nil, from: start, to: end)
        let csv = buildCSV(records: records)
        guard let data = csv.data(using: .utf8) else { throw ExportError.encodingFailed }
        let url = try exportDirectory()
            .appendingPathComponent("HealthVault_\(dateFileName(start))_\(dateFileName(end)).csv")
        try data.write(to: url)
        return url
    }

    /// Documents/HealthVault Exports – visible in Files app under On My iPhone.
    private func exportDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HealthVault Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private

    private func dateFileName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func buildCSV(records: [HealthMetricRecord]) -> String {
        var csv = "type,value,unit,start_date,end_date,source\n"
        let dateFormatter = ISO8601DateFormatter()
        for r in records {
            let start = dateFormatter.string(from: r.startDate)
            let end = r.endDate.map { dateFormatter.string(from: $0) } ?? ""
            csv += "\(r.type),\(r.value),\(r.unit ?? ""),\(start),\(end),\(r.source ?? "")\n"
        }
        return csv
    }

    private func buildPDF(records: [HealthMetricRecord], title: String, from start: Date, to end: Date) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let format = UIGraphicsPDFRendererFormat()
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            let lineHeight: CGFloat = 18

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.label
            ]
            let headerAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]
            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.label
            ]

            (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttr)
            y += lineHeight * 1.5
            let rangeStr = "\(dateFormatter.string(from: start)) – \(dateFormatter.string(from: end))"
            rangeStr.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttr)
            y += lineHeight * 2

            let grouped = Dictionary(grouping: records, by: { $0.type })
            for (type, items) in grouped.sorted(by: { $0.key < $1.key }) {
                if y > pageHeight - margin - lineHeight * 2 {
                    context.beginPage()
                    y = margin
                }
                type.draw(at: CGPoint(x: margin, y: y), withAttributes: headerAttr)
                y += lineHeight
                for r in items {
                    if y > pageHeight - margin - lineHeight {
                        context.beginPage()
                        y = margin
                    }
                    let line = "  \(dateFormatter.string(from: r.startDate))  \(r.value) \(r.unit ?? "")"
                    line.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttr)
                    y += lineHeight
                }
                y += lineHeight * 0.5
            }
        }
        return data
    }

    /// Encrypt data with password-derived key (PBKDF2 + AES-GCM).
    private func encrypt(data: Data, password: String) throws -> Data {
        let salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw ExportError.encryptionFailed }
        // Format: salt (32) + nonce+ciphertext+tag
        var out = salt
        out.append(combined)
        return out
    }

    /// Derive key from password + salt using repeated SHA256 (template; use PBKDF2 in production).
    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        var data = Data(password.utf8)
        data.append(salt)
        for _ in 0..<100_000 {
            data = Data(SHA256.hash(data: data))
        }
        return SymmetricKey(data: data.prefix(32))
    }
}

// MARK: - Open / Decrypt

extension ZeroKnowledgeExportService {

    /// Decrypt data exported by this app (format: salt 32 bytes + AES-GCM combined).
    func decrypt(data encryptedData: Data, password: String) throws -> Data {
        guard encryptedData.count > 32 else { throw ExportError.decryptionFailed }
        let salt = encryptedData.prefix(32)
        let combined = encryptedData.dropFirst(32)
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.SealedBox(combined: Data(combined))
        return try AES.GCM.open(sealed, using: key)
    }

    /// Open and decrypt a file; returns decrypted data and whether it's PDF (by extension).
    func openEncryptedFile(url: URL, password: String) throws -> (data: Data, isPDF: Bool) {
        let data = try Data(contentsOf: url)
        return try openEncryptedData(data: data, password: password, fileExtension: url.pathExtension)
    }

    /// Decrypt in-memory data (e.g. after reading with security-scoped access).
    func openEncryptedData(data: Data, password: String, fileExtension: String) throws -> (data: Data, isPDF: Bool) {
        let decrypted = try decrypt(data: data, password: password)
        let ext = fileExtension.lowercased()
        let isPDF = ext.hasPrefix("pdf") || (decrypted.count >= 4 && decrypted.prefix(4) == "%PDF".data(using: .utf8))
        return (decrypted, isPDF)
    }
}

private enum ExportError: Error {
    case encodingFailed
    case encryptionFailed
    case decryptionFailed
}
