# Schwung Pocket for macOS

A native SwiftUI desktop companion for Ableton Move running Schwung. This is a separate macOS product directory and build target; the existing iOS app remains unchanged.

## Current foundation

- Native macOS navigation: Overview, Move Mirror, Schwung Manager, Studio, Files, Connection.
- Embedded WebKit windows for the known device endpoints.
- Configurable Move base address, persisted in UserDefaults.
- HTTP connectivity check with a visible result.
- A protocol-first Studio placeholder that explicitly avoids sending undocumented commands.

Known default endpoints:
- Manager: `http://move.local:7700/`
- Remote UI: `http://move.local:7700/remote-ui`
- Files: `http://move.local:7700/files`

If the Remote UI route differs on the installed Schwung version, change the route only after confirming it against the running device.

## Build locally

Requires macOS 13+ and Swift 5.9+.

```sh
cd macOS
swift build -c release
```

GitHub Actions builds an unsigned `.app` bundle and publishes it as an artifact. Because it is unsigned, macOS may require the user to explicitly approve opening it. Signing/notarisation can be added later.

## Roadmap

1. Foundation and cloud build (current): native app shell, configurable connection, embedded endpoints.
2. Mirror and connection hardening: verify the installed Move's actual mirror route, show load/network errors, add reconnect and endpoint diagnostics.
3. Manager and Files polish: navigation history, download handling, open-in-Finder and file-operation support only where the server supports it.
4. Native Remote UI: port proven models and protocol handling from the iOS app, preserving observed message formats and slot-label behaviour.
5. Studio controls: hierarchy and parameter discovery, reliable value updates, parameter controls, supported mute/solo.
6. Protocol investigations: Master FX, Tool controls, transport, FX mute granularity, DSP path resolution and hot-swap validation.
7. Packaging: signing, notarisation, versioning, release artifacts and regression checks against the actual Move.

## Verification policy

A successful build proves compilation, not hardware functionality. Every protocol feature must be marked as implemented, build-verified, and device-verified separately.
