//
//  HealthVaultApp.swift
//  HealthVault
//
//  Privacy-first health vault: biometric gate, encrypted storage, data masking.
//

import SwiftUI

@main
struct HealthVaultApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .dataMaskedWhenInactive()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        appState.persistAndLock()
                    }
                }
        }
    }
}
