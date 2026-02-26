//
//  DataMaskingModifier.swift
//  HealthVault
//
//  Blurs sensitive content when the app is in background or inactive
//  (multitasking, app switcher, etc.).
//

import SwiftUI

/// View modifier that overlays a blur when the app is in background or inactive.
struct DataMaskingModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        ZStack {
            content
            if scenePhase != .active {
                DataMaskingOverlay()
            }
        }
    }
}

private struct DataMaskingOverlay: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

extension View {
    /// Apply privacy blur when app is in background or inactive.
    func dataMaskedWhenInactive() -> some View {
        modifier(DataMaskingModifier())
    }
}

#Preview {
    Text("Sensitive data")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dataMaskedWhenInactive()
}
