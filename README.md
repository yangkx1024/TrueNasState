# TrueStats

A lightweight macOS menu-bar app for monitoring a TrueNAS SCALE server. It lives in the status bar, surfaces active alert counts at a glance, and opens a popover with a live dashboard of pools, apps, and realtime system stats.

## Features

- **Dashboard** — system info, pool health, alerts, and a list of installed apps with per-app live CPU/memory.
- **Realtime updates** over the TrueNAS JSON-RPC WebSocket (`reporting.realtime`, `alert.list`, `app.query`, `app.stats`) plus a 30 s snapshot refresh.
- **App upgrades** triggered from the menu, with system-update availability surfaced from `update.check_available`.
- **Keychain-backed credentials** — the API key is stored in the macOS Keychain; the endpoint URL lives in `UserDefaults`.

## Requirements

- macOS 14.0 or later
- Xcode 15+ (Swift 5)
- A TrueNAS SCALE server reachable over `https://` with a user-linked API key

## Building

Open `TrueNasState.xcodeproj` in Xcode and run the `TrueNasState` scheme. The project uses automatic code signing and the hardened runtime; signing requires a local development team.

The app is a status-bar agent — there is no Dock icon and no main window. After launching, look for the drive icon in the menu bar.

## Setup

1. In the TrueNAS web UI, go to **Credentials → Local Users**, pick a user, and create an **API key** linked to that user.
2. Click the menu-bar icon to open the popover and sign in:
   - **Endpoint** — `https://your-nas-host` (only `https://` is accepted)
   - **API key** — paste the key from step 1
3. Right-click the menu-bar icon to open settings (logout, launch-at-login).

Credentials are stored in the Keychain under service `net.yangkx.truestate`.

### Self-hosted TrueNAS with a self-signed certificate

If your TrueNAS server uses a self-signed certificate, the WebSocket connection will fail with a TLS trust error. Add the certificate to your macOS keychain so the app trusts it:

1. In a browser, open `https://your-nas-host` and export the server certificate:
   - **Safari** — click the padlock → **Show Certificate** → drag the certificate icon to your Desktop.
   - **Chrome** — click the padlock → **Connection is not secure** → **Certificate is not valid**, then drag the certificate icon to your Desktop.
   - Or copy `/etc/certificates/<cert-name>.crt` from the TrueNAS host directly.
2. Open **Keychain Access**, select the **login** keychain, and drag the `.crt` file into it.
3. Double-click the imported certificate, expand **Trust**, and set **When using this certificate** to **Always Trust**. Close the window and authenticate to save.
4. Quit and relaunch TrueNasState, then sign in again.

If TrueNAS is reachable only by IP or a `.local` hostname that doesn't match the certificate's Common Name / SAN, regenerate the certificate in TrueNAS (**System → Certificates**) with the hostname or IP you actually use before importing it.

## Project layout

```
TrueNasState/
├── TrueNasStateApp.swift     # @main, wires in AppDelegate
├── AppDelegate.swift         # NSStatusItem + NSPopover, status-bar badge
├── Auth/                     # Keychain credential store, auth state, login item
├── Networking/               # JSON-RPC WebSocket client, typed API methods, reconnect
├── Models/                   # SystemInfo, Pool, App, Alert, RealtimeStats, AppLiveStat
├── ViewModels/               # DashboardViewModel (Observable, @MainActor)
├── Views/                    # SwiftUI views for the popover screens
└── Resources/                # Assets, icons
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
