# HealthVault — Technical Description

A privacy-first iOS application for storing and exporting health data with on-device encryption, biometric protection, and zero-knowledge export.

## Demo video

**[Watch on YouTube (Shorts)](https://youtube.com/shorts/QFGnXs0dQsA?si=Hy17PwVa4sZt9v4h)**

---

## 1. Overview

| Aspect | Description |
|--------|-------------|
| **Platform** | iOS (Swift, SwiftUI); minimum target configurable (e.g. iOS 26 in project). |
| **Architecture** | Local-first: all sensitive data is encrypted on device; no mandatory cloud backend. |
| **Data sources** | Apple Health (HealthKit): steps, sleep analysis, heart rate. Apple Watch data is included when synced via Health. |
| **Export** | Encrypted PDF and CSV (password-derived key); decrypt and open from within the app. |

---

## 2. Architecture

### 2.1 High-level flow

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Health (Kit)   │────▶│  HealthVault      │────▶│  Encrypted SQLite    │
│  (steps, sleep, │     │  (sync, export)   │     │  + Keychain key      │
│   heart rate)   │     └──────────────────┘     └─────────────────────┘
└─────────────────┘              │
                                 ▼
                    ┌────────────────────────────┐
                    │  Biometric (Face ID /      │
                    │  Touch ID / device PIN)    │
                    └────────────────────────────┘
```

- **Entry:** User unlocks with biometrics (or device passcode fallback).
- **Sync:** HealthKit → in-memory processing → `HealthVaultRepository` → encrypted DB.
- **Export:** Repository → generate PDF/CSV → encrypt with user password → file (Documents or share).
- **Open file:** File picker → user password → decrypt → display (PDF or CSV text).

### 2.2 Main components

| Component | Responsibility |
|-----------|----------------|
| **SecureDatabase** | SQLite persistence with AES-GCM file-level encryption; key from Keychain. |
| **HealthVaultRepository** | CRUD for health metrics (steps, sleep, heart rate) against `SecureDatabaseProtocol`. |
| **HealthKitService** | Implements `HealthServiceProtocol`: authorization and read for steps, sleep, heart rate. |
| **ZeroKnowledgeExportService** | Builds PDF/CSV, encrypts with password-derived key; decrypt and open encrypted files. |
| **AppState** | Unlock/lock, sync-from-Health, last-sync time, and count of samples from Apple Watch. |
| **BiometricShieldView** | Reusable gate: Face ID / Touch ID (or device passcode) before showing protected content. |
| **DataMaskingModifier** | Blurs UI when app is in background or inactive (scenePhase). |

---

## 3. Security

### 3.1 On-device encryption (storage)

- **Mechanism:** SQLite DB file is encrypted at rest using **AES-GCM** (CryptoKit). Plaintext DB is used only in a temporary directory while the app is unlocked; on lock or background it is encrypted and written to disk.
- **Key:** 256-bit symmetric key stored in **Keychain** (`kSecClassGenericPassword`, service `com.ugr.HealthVault.secure`). Key is created once and reused.
- **Lock/unlock:** `lock()` closes DB and encrypts the current file to the persistent path. `unlock()` decrypts and reopens. Lock is triggered on app background; unlock after successful biometric auth.

Replacing this with **SQLCipher** (e.g. via GRDB+SQLCipher) is possible by implementing `SecureDatabaseProtocol` with a SQLCipher-backed store.

### 3.2 Biometric and device authentication

- **Policy:** `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` for Face ID / Touch ID. If biometrics are not enrolled, fallback uses `.deviceOwnerAuthentication` (device passcode).
- **Usage:** `BiometricShieldView` wraps the main content; after success, `AppState.unlock()` is called and the vault DB is unlocked.
- **Info.plist:** `NSFaceIDUsageDescription` is set for Face ID.

### 3.3 Data masking

- **When:** App is not in foreground (`scenePhase != .active`): e.g. background or app switcher.
- **How:** `DataMaskingModifier` overlays a full-screen blur (e.g. `.ultraThinMaterial`) with a lock icon so no sensitive content is visible.

### 3.4 Zero-knowledge export

- **Format:** Encrypted blob = **32-byte salt** (random) + **AES-GCM** `combined` (nonce + ciphertext + tag).
- **Key derivation:** From user password + salt: 100_000 iterations of SHA-256 (password+salt) then first 32 bytes as key. For production, consider PBKDF2 or similar.
- **File types:** `.csv.enc`, `.pdf.enc`. Decryption and open-from-file use the same format and password.

---

## 4. Data storage

### 4.1 Schema (SQLite)

Single table for all metric types:

```sql
CREATE TABLE health_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,           -- 'steps' | 'sleep_hours' | 'heart_rate'
    value REAL NOT NULL,
    unit TEXT,
    start_date REAL NOT NULL,
    end_date REAL,
    source TEXT,                 -- e.g. "Apple Watch", "iPhone"
    created_at REAL NOT NULL
);
CREATE INDEX idx_health_metrics_type ON health_metrics(type);
CREATE INDEX idx_health_metrics_dates ON health_metrics(start_date, end_date);
```

### 4.2 File locations

- **Encrypted DB:** `Application Support/HealthVault/vault.sqlite.enc`
- **Decrypted (temporary):** `Application Support/HealthVault/tmp/vault_decrypted.sqlite` (removed when locked)
- **Exports:** `Documents/HealthVault Exports/` (visible in Files app when `UIFileSharingEnabled` is set)

---

## 5. Health integration

### 5.1 HealthKit (iOS)

- **Types read:** Step count (`HKQuantityTypeIdentifier.stepCount`), heart rate (`heartRate`), sleep analysis (`HKCategoryTypeIdentifier.sleepAnalysis`).
- **No write:** App only requests read authorization.
- **Apple Watch:** Watch syncs to Health automatically; HealthKit samples include `sourceRevision.source.name` (e.g. "Apple Watch"). The app counts samples from "Apple Watch" and displays “Last sync included N readings from Apple Watch” when relevant.
- **Capability:** Requires **HealthKit** in Signing & Capabilities and corresponding App ID entitlement. Info.plist uses `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`.

### 5.2 Health service abstraction

- **Protocol:** `HealthServiceProtocol` defines `isAvailable()`, `requestAuthorization()`, `fetchSteps`, `fetchSleep`, `fetchHeartRate`.
- **iOS:** `HealthKitService` implements it using `HKHealthStore`.
- **Android:** Not included; a future Android app can implement the same protocol using **Health Connect** (see `Health/HealthConnectPlaceholder.md`).

---

## 6. Export and open file

### 6.1 Export

- **Formats:** Encrypted CSV (`.csv.enc`) or PDF (`.pdf.enc`).
- **Password:** User-entered; used only for key derivation (salt + iterative SHA-256). Same password is required to open the file later.
- **Output:** Files are written to `HealthVault Exports`; user can share/save via `ShareLink` or Files.

### 6.2 Open encrypted file

- **Flow:** User chooses a file (e.g. from Files or export folder), enters password, app decrypts and displays content.
- **Security-scoped access:** For files outside the app container, `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` are used around reading the file.
- **Display:** PDF via `PDFKit.PDFView`; CSV as plain text in a scrollable view.

---

## 7. UI structure

- **HealthVaultApp:** Root scene; applies `DataMaskingModifier` and on `scenePhase == .background` calls `AppState.persistAndLock()`.
- **ContentView:** If unlocked, shows `DashboardView`; otherwise shows `BiometricShieldView` wrapping the dashboard (unlock calls `AppState.unlock()`).
- **DashboardView:** Sync from Health, Apple Watch & Bluetooth explanation, export, open encrypted file. Export and open file use sheets (export form, `OpenEncryptedFileView`).
- **BiometricShieldView:** Reusable; supports Face ID / Touch ID and “Unlock with device passcode” when biometrics are unavailable.

---

## 8. Requirements and setup

### 8.1 Requirements

- Xcode (project uses Swift 5, SwiftUI).
- iOS target as set in project (e.g. iOS 26).
- **HealthKit:** Enable HealthKit capability and configure App ID if using “Sync from Health” on a physical device.
- **Face ID:** Device with Face ID or Touch ID (or passcode fallback) for biometric shield.

### 8.2 Capabilities and Info.plist

- **HealthKit** (optional but needed for sync): Add in Signing & Capabilities; ensure HealthKit entitlement in App ID.
- **Info.plist (or target settings):**
  - `NSHealthShareUsageDescription`
  - `NSHealthUpdateUsageDescription`
  - `NSFaceIDUsageDescription`
  - `UIFileSharingEnabled` = YES (for export folder in Files)
  - `LSSupportsOpeningDocumentsInPlace` = YES (optional)

### 8.3 Running on device

```bash
# Build
xcodebuild -scheme HealthVault -destination 'id=<DEVICE_UDID>' -allowProvisioningUpdates build

# Install and launch (replace DEVICE_UDID)
xcrun devicectl device install app --device <DEVICE_UDID> \
  "$(find ~/Library/Developer/Xcode/DerivedData -name 'HealthVault.app' -path '*/Debug-iphoneos/*' | head -1)"
xcrun devicectl device process launch --device <DEVICE_UDID> com.ugr.HealthVault
```

---

## 9. Project layout (main app)

```
HealthVault/
├── HealthVaultApp.swift          # @main, scenePhase, data masking
├── ContentView.swift             # Biometric gate + dashboard
├── App/
│   ├── AppState.swift            # Unlock/lock, sync, lastSyncFromWatchCount
│   ├── DashboardView.swift       # Sync, export, open file, Apple Watch section
│   └── OpenEncryptedFileView.swift  # File picker, password, PDF/CSV viewer
├── Biometric/
│   └── BiometricShieldView.swift # Face ID / Touch ID / passcode gate
├── Health/
│   ├── HealthServiceProtocol.swift
│   ├── HealthKitService.swift
│   └── HealthConnectPlaceholder.md
├── SecureStorage/
│   ├── SecureDatabase.swift      # Encrypted SQLite, Keychain key
│   └── HealthVaultRepository.swift
├── Export/
│   └── ZeroKnowledgeExportService.swift  # PDF/CSV build, encrypt, decrypt
├── Privacy/
│   └── DataMaskingModifier.swift # Blur when inactive
├── HealthVault.entitlements
└── Assets.xcassets
```

---

## 10. Technical decisions (summary)

| Decision | Rationale |
|----------|-----------|
| File-level DB encryption (CryptoKit) | Works with system SQLite; no SQLCipher build. Can be swapped for SQLCipher via `SecureDatabaseProtocol`. |
| Key in Keychain | Key survives app updates; not in UserDefaults or plain files. |
| Lock on background | Reduces window where plaintext DB exists; re-auth required on return. |
| Password-based export key | User-controlled secret; no server; same password to open later. |
| HealthKit only for health data | Apple’s supported path; Watch data flows through Health. |
| No direct Watch Bluetooth API | Health data from Watch is only exposed via Health; no app-level Bluetooth connection to Watch. |

---

## 11. License and contact

Project-specific. Adjust as needed for your organization.
# AppleHeathExport
