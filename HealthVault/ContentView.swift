//
//  ContentView.swift
//  HealthVault
//
//  Root view: gates content behind BiometricShield, then shows dashboard.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.isUnlocked {
                DashboardView(appState: appState)
            } else {
                BiometricShieldView(
                    reason: "Unlock HealthVault to view your health data",
                    onAuthenticated: { appState.unlock() }
                ) {
                    DashboardView(appState: appState)
                }
            }
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}
