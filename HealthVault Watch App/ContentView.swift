//
//  ContentView.swift
//  HealthVault Watch App
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("HealthVault", systemImage: "lock.shield.fill")
                    .font(.headline)
                Text("Apple Watch data syncs to your iPhone through the Health app. Open HealthVault on your iPhone and tap \"Sync from Health\" to pull in your steps, heart rate, and sleep—including from this watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
