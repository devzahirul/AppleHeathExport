# HealthVault Watch App

## Add this target in Xcode

1. **File → New → Target**
2. Choose **watchOS → Watch App** (not Watch App for iOS App).
3. Product name: **HealthVault Watch App**
4. Uncheck "Include Notification Scene" if you don’t need it.
5. Click **Finish**. Xcode will create a new target and its scheme.
6. **Replace** the generated `ContentView.swift` and `HealthVaultWatchApp.swift` with the ones in this folder (they’re already written for HealthVault).
7. Build and run: choose the **HealthVault Watch App** scheme and a Watch simulator or paired Watch.

## How Apple Watch connects

- Your **Apple Watch** sends steps, heart rate, and sleep to the **Health** app on your iPhone.
- In the **HealthVault** iPhone app, tap **Sync from Health** and allow access when prompted.
- HealthVault then reads that data from Health (including all Watch data) and stores it in your encrypted vault.

No extra “connect Watch” step is needed: **Watch → Health → HealthVault** when you sync.
