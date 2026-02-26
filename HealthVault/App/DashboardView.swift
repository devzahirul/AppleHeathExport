//
//  DashboardView.swift
//  HealthVault
//
//  Main dashboard: sync from Health, view summary, export encrypted reports.
//

import SwiftUI

private enum ExportFormatChoice: String, CaseIterable {
    case csv
    case pdf
}

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var exportPassword = ""
    @State private var showExportSheet = false
    @State private var showOpenFileSheet = false
    @State private var exportFormatChoice: ExportFormatChoice = .csv
    @State private var exportedURL: URL?
    @State private var exportMessage: String?

    private var calendar: Calendar { Calendar.current }
    private var weekStart: Date {
        calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Health Sync") {
                    Button {
                        Task { await appState.syncFromHealth() }
                    } label: {
                        Label("Sync from Health", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!appState.isUnlocked)
                    if let date = appState.lastSyncDate {
                        Text("Last sync: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let err = appState.syncError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Apple Watch & Bluetooth") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How Watch connects", systemImage: "applewatch")
                        Text("Your Apple Watch connects to this iPhone via Bluetooth. Pair it in the Watch app (or Settings → Bluetooth). HealthVault gets Watch data through the Health app when you sync—no separate connection in the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("1. Pair Watch: iPhone Settings → Watch (or open the Watch app). 2. Sync: Tap \"Sync from Health\" above; Health will include data from your Watch.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if appState.lastSyncFromWatchCount > 0 {
                            Text("Last sync included \(appState.lastSyncFromWatchCount) readings from Apple Watch.")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("Export (Zero-Knowledge)") {
                    Button {
                        showExportSheet = true
                    } label: {
                        Label("Export Encrypted Report", systemImage: "lock.doc")
                    }
                    .disabled(appState.exportService == nil)
                    Button {
                        showOpenFileSheet = true
                    } label: {
                        Label("Open Encrypted File", systemImage: "lock.open")
                    }
                    .disabled(appState.exportService == nil)
                }
            }
            .navigationTitle("HealthVault")
            .sheet(isPresented: $showExportSheet) {
                exportSheet
            }
            .sheet(isPresented: $showOpenFileSheet) {
                OpenEncryptedFileView(exportService: appState.exportService)
            }
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            Form {
                Picker("Format", selection: $exportFormatChoice) {
                    Text("Encrypted CSV").tag(ExportFormatChoice.csv)
                    Text("Encrypted PDF").tag(ExportFormatChoice.pdf)
                }
                .pickerStyle(.segmented)
                SecureField("Export password", text: $exportPassword)
                    .textContentType(.password)
                if let msg = exportMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("Saved") ? .green : .red)
                }
                if let url = exportedURL {
                    Section {
                        ShareLink(item: url, subject: Text("HealthVault Export"), message: Text("Encrypted health report. Use your export password to decrypt.")) {
                            Label("Share / Save to Files", systemImage: "square.and.arrow.up")
                        }
                        Text("Tap above to save to Files, AirDrop, or share. Remember your password to decrypt later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showExportSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        performExport()
                    }
                    .disabled(exportPassword.isEmpty)
                }
            }
        }
        .onAppear {
            exportMessage = nil
            exportPassword = ""
        }
    }

    private func performExport() {
        guard let export = appState.exportService else { return }
        let password = exportPassword
        Task {
            do {
                let url: URL
                if exportFormatChoice == .pdf {
                    url = try await export.exportEncryptedPDF(
                        from: weekStart,
                        to: Date(),
                        password: password
                    )
                } else {
                    url = try await export.exportEncryptedCSV(
                        from: weekStart,
                        to: Date(),
                        password: password
                    )
                }
                await MainActor.run {
                    exportedURL = url
                    exportMessage = "Saved to HealthVault Exports. Use Share below to save to Files or elsewhere. Use the same password to decrypt."
                }
            } catch {
                await MainActor.run {
                    exportMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    DashboardView(appState: AppState())
}
