//
//  BiometricShieldView.swift
//  HealthVault
//
//  Reusable UI component that gates content behind Face ID / Touch ID.
//

import SwiftUI
import LocalAuthentication

enum BiometricState: Equatable {
    case idle
    case authenticating
    case authenticated
    case failed(String)
    case unavailable(String)
}

/// Reusable view that requires biometric authentication before revealing content.
struct BiometricShieldView<Content: View>: View {
    let reason: String
    let content: () -> Content
    let onAuthenticated: () -> Void
    let onUnavailable: ((String) -> Void)?

    @State private var state: BiometricState = .idle
    @State private var didAttemptOnAppear = false

    init(
        reason: String = "Unlock HealthVault to view your health data",
        onAuthenticated: @escaping () -> Void = {},
        onUnavailable: ((String) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.reason = reason
        self.onAuthenticated = onAuthenticated
        self.onUnavailable = onUnavailable
        self.content = content
    }

    var body: some View {
        Group {
            switch state {
            case .authenticated:
                content()
            case .unavailable(let message):
                unavailableView(message: message)
            case .failed(let message):
                failedView(message: message)
            default:
                shieldOverlay
            }
        }
        .task {
            guard !didAttemptOnAppear else { return }
            didAttemptOnAppear = true
            await authenticate()
        }
        .onChange(of: state) { _, newState in
            if case .authenticated = newState {
                onAuthenticated()
            }
        }
    }

    private var shieldOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: biometricIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("HealthVault Locked")
                    .font(.title2.weight(.semibold))
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if case .authenticating = state {
                    ProgressView()
                        .padding(.top, 8)
                } else if case .idle = state {
                    Button("Unlock with \(biometricTypeName)") {
                        Task { await authenticate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func unavailableView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Biometrics Unavailable")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("You can still unlock with your device passcode.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Unlock with device passcode") {
                Task { await authenticateWithPasscode() }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Authentication Failed")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Button("Try Again") {
                state = .idle
                Task { await authenticate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var biometricTypeName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Biometrics"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometrics"
        }
    }

    private var biometricIcon: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "lock.fill"
        }
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.fill"
        }
    }

    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            await MainActor.run {
                state = .unavailable(error?.localizedDescription ?? "Biometrics are not available.")
                onUnavailable?(error?.localizedDescription ?? "Biometrics are not available.")
            }
            return
        }
        await MainActor.run { state = .authenticating }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            await MainActor.run {
                state = success ? .authenticated : .failed("Authentication was not successful.")
            }
        } catch {
            await MainActor.run {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Fallback when Face ID/Touch ID isn't enrolled: use device passcode.
    private func authenticateWithPasscode() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            await MainActor.run {
                state = .failed(error?.localizedDescription ?? "Device passcode is not available.")
            }
            return
        }
        await MainActor.run { state = .authenticating }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock HealthVault with your device passcode"
            )
            await MainActor.run {
                state = success ? .authenticated : .failed("Authentication was not successful.")
            }
        } catch {
            await MainActor.run {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

/// Environment key to trigger re-lock (e.g. when app goes to background).
struct BiometricReLockKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var biometricReLock: (() -> Void)? {
        get { self[BiometricReLockKey.self] }
        set { self[BiometricReLockKey.self] = newValue }
    }
}

#Preview {
    BiometricShieldView(reason: "Preview unlock") {
        Text("Secret content")
    }
}
