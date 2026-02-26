//
//  SecureDatabase.swift
//  HealthVault
//
//  On-device encrypted SQLite storage. Uses CryptoKit for file-level encryption
//  with key stored in Keychain. For SQLCipher-based encryption, replace this
//  with a GRDB+SQLCipher implementation using the same SecureDatabaseProtocol.
//

import Foundation
import CryptoKit
import Security
import SQLite3

/// Protocol for encrypted persistence; allows swapping to SQLCipher/GRDB later.
protocol SecureDatabaseProtocol: Sendable {
    func execute(_ sql: String, parameters: [Any]?) throws
    func query(_ sql: String, parameters: [Any]?) throws -> [[String: Any]]
    func close() throws
}

/// Keychain-backed key storage for database encryption.
enum KeychainKeyStore {
    private static let service = "com.ugr.HealthVault.secure"
    private static let keyAccount = "db_encryption_key"

    static func getOrCreateKey() throws -> SymmetricKey {
        if let existing = try getKey() {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        try saveKey(newKey)
        return newKey
    }

    private static func getKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureDatabaseError.keychainWriteFailed
        }
    }
}

enum SecureDatabaseError: Error {
    case keychainWriteFailed
    case encryptionFailed
    case decryptionFailed
    case sqliteError(String)
    case fileNotFound
}

/// Encrypted SQLite database: plain SQLite file is encrypted at rest with AES-GCM.
final class SecureDatabase: SecureDatabaseProtocol, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let encryptedURL: URL
    private let tempDirectory: URL
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.ugr.HealthVault.secureDb", qos: .userInitiated)

    init() throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let healthVault = appSupport.appendingPathComponent("HealthVault", isDirectory: true)
        try fileManager.createDirectory(at: healthVault, withIntermediateDirectories: true)
        encryptedURL = healthVault.appendingPathComponent("vault.sqlite.enc")
        tempDirectory = healthVault.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try openDecrypted()
        try createSchemaIfNeeded()
    }

    private var decryptedURL: URL {
        tempDirectory.appendingPathComponent("vault_decrypted.sqlite")
    }

    private func openDecrypted() throws {
        let key = try KeychainKeyStore.getOrCreateKey()
        if fileManager.fileExists(atPath: encryptedURL.path) {
            let encryptedData = try Data(contentsOf: encryptedURL)
            let decrypted = try decrypt(data: encryptedData, key: key)
            try decrypted.write(to: decryptedURL)
        }
        if sqlite3_open_v2(decryptedURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            throw SecureDatabaseError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func createSchemaIfNeeded() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS health_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            value REAL NOT NULL,
            unit TEXT,
            start_date REAL NOT NULL,
            end_date REAL,
            source TEXT,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_health_metrics_type ON health_metrics(type);
        CREATE INDEX IF NOT EXISTS idx_health_metrics_dates ON health_metrics(start_date, end_date);
        """
        try execute(schema, parameters: nil)
    }

    func execute(_ sql: String, parameters: [Any]? = nil) throws {
        try queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SecureDatabaseError.sqliteError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            if let params = parameters {
                for (index, value) in params.enumerated() {
                    let pos = Int32(index + 1)
                    switch value {
                    case let v as Int: sqlite3_bind_int64(statement, pos, Int64(v))
                    case let v as Int64: sqlite3_bind_int64(statement, pos, v)
                    case let v as Double: sqlite3_bind_double(statement, pos, v)
                    case let v as String: sqlite3_bind_text(statement, pos, (v as NSString).utf8String, -1, nil)
                    case is NSNull: sqlite3_bind_null(statement, pos)
                    default: sqlite3_bind_text(statement, pos, String(describing: value).cString(using: .utf8), -1, nil)
                    }
                }
            }
            if sqlite3_step(statement) != SQLITE_DONE {
                throw SecureDatabaseError.sqliteError(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func query(_ sql: String, parameters: [Any]? = nil) throws -> [[String: Any]] {
        try queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SecureDatabaseError.sqliteError(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            if let params = parameters {
                for (index, value) in params.enumerated() {
                    let pos = Int32(index + 1)
                    switch value {
                    case let v as Int: sqlite3_bind_int64(statement, pos, Int64(v))
                    case let v as Int64: sqlite3_bind_int64(statement, pos, v)
                    case let v as Double: sqlite3_bind_double(statement, pos, v)
                    case let v as String: sqlite3_bind_text(statement, pos, (v as NSString).utf8String, -1, nil)
                    case is NSNull: sqlite3_bind_null(statement, pos)
                    default: sqlite3_bind_text(statement, pos, String(describing: value).cString(using: .utf8), -1, nil)
                    }
                }
            }
            var rows: [[String: Any]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let count = sqlite3_column_count(statement)
                for i in 0..<count {
                    let name = String(cString: sqlite3_column_name(statement, i))
                    switch sqlite3_column_type(statement, i) {
                    case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, i)
                    case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, i)
                    case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, i))
                    default: row[name] = NSNull()
                    }
                }
                rows.append(row)
            }
            return rows
        }
    }

    /// Persist current DB to encrypted file (call before backgrounding or locking).
    func encryptAndPersist() throws {
        try queue.sync {
            guard let d = db else { return }
            sqlite3_close(d)
            db = nil
        }
        let plainData = try Data(contentsOf: decryptedURL)
        let key = try KeychainKeyStore.getOrCreateKey()
        let encrypted = try encrypt(data: plainData, key: key)
        try encrypted.write(to: encryptedURL)
        try? fileManager.removeItem(at: decryptedURL)
        try openDecrypted()
    }

    /// Lock vault: encrypt on disk and clear in-memory DB until next unlock.
    func lock() throws {
        try queue.sync {
            guard let d = db else { return }
            sqlite3_close(d)
            db = nil
        }
        if fileManager.fileExists(atPath: decryptedURL.path) {
            let plainData = try Data(contentsOf: decryptedURL)
            let key = try KeychainKeyStore.getOrCreateKey()
            try encrypt(data: plainData, key: key).write(to: encryptedURL)
            try fileManager.removeItem(at: decryptedURL)
        }
    }

    /// Reopen database after lock(); call after successful biometric auth.
    func unlock() throws {
        if db != nil { return }
        try openDecrypted()
    }

    func close() throws {
        try encryptAndPersist()
        if let d = db {
            sqlite3_close(d)
            db = nil
        }
    }

    // MARK: - CryptoKit AES-GCM

    private func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw SecureDatabaseError.encryptionFailed }
        return combined
    }

    private func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealed, using: key)
    }
}
