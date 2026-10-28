# Schwung Pocket macOS Roadmap

**Branch:** `macos-app`  
**Parity reference:** `v0.9-development`  
**Sync policy:** Review `v0.9-development` before each macOS feature/protocol task. Port applicable behaviour and supporting knowledge selectively; do not merge the iOS branch wholesale.  
**Rule:** The iOS v0.9 branch is the feature and protocol reference. Port behaviour and protocol knowledge where applicable, but adapt presentation and lifecycle to macOS. Do not copy iOS-only navigation or UIKit implementation literally. Do not merge or push to `main` without explicit approval.

## Status key

- **Implemented:** present in macOS source.
- **Build-verified:** GitHub Actions compiled and packaged the current source.
- **Needs runtime check:** compiled but not yet verified in the macOS app.
- **Needs Move verification:** must be tested against a physical Ableton Move running Schwung.
- **Planned:** not implemented yet.

## P0: Stabilise the current macOS SchwungTroller

- [x] Four-slot mixer in one row, vertical 0–400% faders, 100% reference, percentage, Mute and Solo.
- [x] Four-position signal-chain presentation with component state and separate Bypass/Enable and Clear controls.
- [x] Install/Swap menus positioned beside their chain positions.
- [x] Collapsible Connection, Mixer, Signal Chain, Installed Modules, Parameter Controls and Slot Settings sections.
- [x] Hide the redundant window title using the scene-level hidden-title-bar style.
- [ ] Verify latest GitHub Actions artifact opens and the layout is usable at normal and narrow window sizes.
- [ ] Confirm mixer volume, mute/solo, bypass, clear and module swap against the physical Move.

## P1: Port iOS v0.9 SchwungTroller behaviour

- [ ] **Persistent section ordering.** Match the iOS section model: Connection & MIDI Activity, Four-slot Mixer, Signal Chain & Installed Modules, Parameter Controls, Slot Settings. Add Settings controls to move sections up/down, save automatically, and render sections in the saved order.
- [ ] **Persistent collapse state.** Preserve the user's expanded/collapsed choices where practical, using macOS preferences rather than copying iOS storage assumptions blindly.
- [ ] **Live MIDI activity.** Reuse the protocol/event interpretation from iOS `MirrorMIDIActivityStore` and its remote-control event source. Turn the indicator green on real incoming Note/CC activity, show `MIDI ACTIVE`, return to yellow and `MIDI INACTIVE` after 1–2 seconds without activity, and keep the event log collapsible inside Connection.
- [ ] **Connection display parity.** Port the current iOS connection status, reconnect/timeout feedback and lifecycle recovery where relevant. Keep one authoritative connection state and avoid opening duplicate sockets.
- [ ] **Section organisation.** Combine Signal Chain and Installed Modules under the same logical section if this matches the iOS v0.9 section model; keep installation controls compact to the right of each position.
- [ ] **Avoid duplicate controls.** Keep parameter controls scoped to the selected component and retain the parameter-group selector inside Parameter Controls.

## P2: Port protocol and feature improvements from iOS v0.9

- [ ] Compare the latest iOS remote-control store and models against macOS before changing protocol handling.
- [ ] Port fixes for boolean mute/solo values and state refreshes, where the macOS protocol path differs.
- [ ] Preserve dynamic MIDI FX/audio FX chain capacity and positional mapping; do not hard-code four positions if Schwung reports more.
- [ ] Keep Master FX, Tool custom UI and metadata-driven parameter behaviour aligned with verified iOS protocol handling.
- [ ] Keep unsupported or metadata-poor parameters read-only. Never infer write protocol from parameter names alone.
- [ ] Review reconnect, foreground/background and tab/window lifecycle handling to prevent stale state or duplicate subscriptions.

## P3: Desktop-specific quality and regression

- [ ] Use native macOS layout, keyboard focus and window resizing rather than reproducing the iPhone bottom-tab UI.
- [ ] Test hidden-title-bar layout, sidebar visibility, compact/wide window sizes and scrolling.
- [ ] Verify app packaging and artifact launch from GitHub Actions.
- [ ] Run a regression pass for Slots 1–4, empty chains, missing metadata, disconnect/reconnect, Master FX, Tool and module swap.
- [ ] Record build verification separately from physical Move verification.

## Current implementation notes

- Current macOS target: `macOS/Sources/SchwungPocketMac/`.
- Current iOS reference source: `files for chatgpt/SchwungPocket/` on `v0.9-development`.
- iOS v0.9 already includes reorderable/collapsible SchwungTroller sections, persisted section order, vertical faders, and a real MIDI activity store. macOS must port these behaviours, not leave placeholder MIDI state.
- The last confirmed macOS build pass before this roadmap is GitHub Actions run [#30](https://github.com/chutneyrebel/schwung-pocket/actions/runs/40713135033), commit `b91d8f7`. Build success confirms compile/package only, not runtime or Move hardware behaviour.

## Ongoing iOS-to-macOS sync workflow

1. Before each macOS task, inspect new commits and relevant source changes on `v0.9-development` since the last parity review.
2. Compare iOS and macOS implementations for the affected feature, protocol messages, models, connection lifecycle, release notes and supporting documentation.
3. Record applicable additions, protocol differences, and macOS-specific adaptations in this roadmap or task notes.
4. Port only applicable changes to `macos-app`; do not copy UIKit/SwiftUI iOS navigation or platform-only code verbatim.
5. Build with GitHub Actions after each focused port and report build status separately from hardware validation.
6. Keep a parity ledger with reference commit SHA, affected feature, macOS port status and verification status.
7. Never merge branches or change `main` without explicit user approval.

## Parity ledger

| Area | iOS reference | macOS status |
|---|---|---|
| SchwungTroller section order and collapsed state | `NativeControlsScreen.swift` on `v0.9-development` | Planned |
| Live MIDI event bridge and activity log | `ManagerWebView.swift` + `NativeControlsScreen.swift` on `v0.9-development` | Planned; macOS WebKit bridge required |
| Remote UI WebSocket and connection recovery | `RemoteControlStore.swift` on `v0.9-development` | Compare and port differences |
| Slot mapping, volume, mute/solo, module chain | `RemoteControlStore.swift` + `RemoteControlModels.swift` on `v0.9-development` | Partial; needs parity audit |
| Release notes and protocol support details | `RELEASE_NOTES.md` on `v0.9-development` | Review on each sync |

## Working rules

1. Work only on `macos-app` unless explicitly approved otherwise.
2. Use `v0.9-development` as the iOS behaviour reference.
3. Make one focused change per build and report a short change summary.
4. Run GitHub Actions after code changes; inspect compiler logs on failure before adding more work.
5. Do not claim a protocol feature works on the physical Move until tested there.
