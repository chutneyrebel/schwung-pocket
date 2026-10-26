# Schwung Pocket Release Notes & Regression Guide

> **Purpose:** These cumulative notes ship with every build so testers can re-check existing behaviour, not only the newest change.
>
> **Branch:** `v0.8.3-development`  
> **Source of truth:** `files for chatgpt/SchwungPocket/` and the sibling `files for chatgpt/SchwungPocket.xcodeproj/`.  
> **Safety:** Do not merge or push this work to `main` unless explicitly requested.

## Build status key

- **Implemented:** present in the app source.
- **Build-verified:** compiled and packaged by GitHub Actions. This does not prove device or Move hardware behaviour.
- **Partially tested:** some user/device testing has been reported, but the full matrix has not been completed.
- **Pending hardware verification:** requires testing with the physical Ableton Move running Schwung.
- **Planned / not confirmed:** not to be treated as a working feature.

## New additions in the current development line

### Tool custom Web UI panel
- Added handling for Schwung's `custom_ui` message for the Tool target, including the advertised component and URL.
- Added an embedded WebKit panel for a supported Tool custom UI URL.
- The resolver attempts to keep the embedded UI on the same Move host and port, uses the Move connection's base scheme, and adds standalone Tool query parameters.
- Added empty-state messaging for Tools that expose neither flat parameter values nor a custom web UI.
- **Status:** implemented in source; latest fix changed URLComponents construction for current Xcode SDK. A successful post-fix build and physical Move test must be confirmed before calling this verified.

## Earlier improvements

### App shell, navigation and layout
- SwiftUI iPhone companion app organised around Home, Modules, Mirror, Manager, Files and Settings.
- Module destinations include SchwungTroller, Sample Lab and Groove Toolkit.
- Configurable bottom-tab ordering, with migration handling for older saved tab layouts.
- Configurable navigation auto-hide behaviour and timeout.
- Settings remains the final tab; Files is preserved when migrating older tab-order preferences.
- Safe-area/footer spacing fixes were made for Home, Modules, Manager, Files and Settings.
- Mirror layout recalculation and Files navigation migration were implemented in the v0.8.3 line.
- App version display was updated to 0.8.3.

### Move connection and web interfaces
- Default Move/Schwung Manager address is `move.local:7700`.
- Saved Move profiles and editable connection address.
- Connection probe timeout and visible connection state.
- Mirror and Manager screens access the Move-hosted web interfaces over the local network.
- Foreground/background recovery support exists in the remote-control connection flow.
- **Known limitation:** an earlier Android 4.4.4 browser/mirror attempt displayed mostly text and the mirror display was reported not working. Do not treat Mirror as hardware-verified; retest it on the iPhone and Move.

### SchwungTroller / Native Controls
- Destination selection for supported instrument slots and remote-control targets.
- Metadata-driven rotary controls, switches and selectors where Schwung provides parameter metadata.
- Instrument signal-chain presentation for the synth, MIDI FX and audio FX.
- Dynamic signal-chain components and positions based on reported capacities.
- Slot chain parsing supports modern positional arrays `midi_fx` and `fx`, capacity fields `midi_fx_cap` and `fx_cap`, and legacy field fallbacks.
- Chain parameter updates support `midi_fx1...midi_fx8`, `fx1...fx8`, `synth`, and `master_fx:fx1...fx8`.
- Capacity handling is capped at eight positions for MIDI/audio FX fallback parsing.
- Remote-control retry/backoff, app foreground/background recovery and optional diagnostics/report copying.
- Prior user-reported testing: instrument Slots 1–4 passed basic testing. This is not a substitute for a complete regression pass on each build.

### Master FX protocol support
- Added Master FX discovery and subscription handling.
- Parses current responses using an `fx` array plus `cap`, and legacy separate `fx1...fx4` fields.
- Master FX capacity is limited to the supported display range and the UI shows only positions reported by the device.
- Parses parameter metadata and values for the selected Master FX component.
- Uses Schwung's `set_master_fx_param` write message for supported parameter changes.
- Improved handling of unknown/invalid Master FX listings, preserving known names where appropriate and clearing discovery timeout state.
- **Status:** code path implemented; live discovery, metadata, values and writes still require a fresh physical Move test.

### Tool protocol and parameter safety
- Added Tool subscription/discovery handling and processing of `tool_info` and Tool parameter updates.
- Tool discovery no longer depends on receiving flat parameter values after `tool_info`.
- Tool data can include `overtake_dsp:` values.
- Tool state without reliable parameter type/range metadata remains read-only. Do not make generic Tool controls editable based only on parameter names.
- Tool custom UI support is described in “New additions in the current development line” above.
- **Status:** protocol discovery logic implemented; actual Tool custom UI compatibility and interactions require physical testing.

### Sample Lab
- Local audio import and audition/playback on the iPhone.
- Intended as a local sample workspace/shelf.
- **Known limitation:** confirmed transfer of samples to the Move has not been established. Do not advertise or test this as a working Move upload feature unless separately verified.

### Groove Toolkit
- Pattern sketching with three 16-step drum lanes.
- Exports a one-bar MIDI file.
- **Regression check:** verify pattern editing and MIDI export/opening. Do not assume the MIDI is automatically transferred or loaded onto the Move.

### Files and app preferences
- Files destination accesses the file interface exposed by Schwung.
- Navigation ordering and auto-hide preferences persist through app storage.
- Older saved tab-order preferences are migrated so Files and Modules are not lost.
- **Regression check:** verify the file interface loads, navigation works, and the app returns to the correct screen after leaving and reopening it.

### Build and delivery workflow
- GitHub Actions builds on pushes to `v0.8.3-development`, manual workflow dispatch, and pull requests targeting `main`.
- Workflow locates the Xcode project or supported source archive, generates a shared Xcode scheme, parses Swift sources, runs an unsigned Release build for iPhoneOS, packages an unsigned IPA, and uploads the IPA and build log.
- Artifacts are retained for seven days.
- A green workflow confirms syntax/build/package steps only. It does not confirm installation, runtime behaviour, network connectivity or hardware control.

## Fixed / compatibility work recorded so far

- Improved Mirror layout recalculation.
- Migrated Files navigation into the current tab structure.
- Preserved the Files destination during older tab-order preference migration.
- Added compatibility parsing for modern and legacy Schwung FX chain payloads.
- Added support for positional MIDI FX/audio FX chain parameter components.
- Added fallback and timeout handling for Tool and Master FX discovery.
- Limited FX capacity parsing to a supported maximum of eight positions.
- Corrected Master FX UI to show only positions reported by the device.
- Fixed Swift SDK compatibility for parsing the Tool custom UI URL by using `URL(string:)` followed by `URLComponents(url:resolvingAgainstBaseURL:)`.
- Earlier build/package workflow was verified on commit `d7bae336fa5b451e25f08a2d9e1f23818338b47f`. The subsequent Tool custom UI URL fix needs a fresh successful workflow result before it is considered build-verified.

## Regression checklist for every build

Record **Pass / Fail / Not tested**, the device/Move setup, and notes for each item.

### A. Installation and app shell
- [ ] IPA artifact exists and workflow is green.
- [ ] Install/launch on the target iPhone; confirm no immediate crash.
- [ ] Home, Modules, Mirror, Manager, Files and Settings tabs open.
- [ ] Bottom safe-area/footer spacing is correct on all tabs.
- [ ] Settings remains at the far right; custom tab order persists after relaunch.
- [ ] Navigation auto-hide setting and timeout work as configured.
- [ ] Version/build identifier matches the build notes.

### B. Connection and network
- [ ] Connect to the Move at the configured address (default `move.local:7700`).
- [ ] Connection status changes correctly when Move is reachable/unreachable.
- [ ] Saved profiles and address changes persist and reconnect correctly.
- [ ] Background the app, return to foreground, and check recovery.
- [ ] Test timeout/retry behaviour when the Move is temporarily unavailable.

### C. Mirror and Manager
- [ ] Manager loads the expected Schwung Manager page.
- [ ] Mirror displays the Move remote UI rather than a text-only fallback.
- [ ] Mirror layout, scaling, scrolling and fullscreen/available controls behave correctly.
- [ ] Physical Move actions and on-screen interactions remain in sync where supported.
- [ ] Test audio-related mirror behaviour separately; it was previously untested.

### D. SchwungTroller instrument slots
- [ ] Test Slots 1, 2, 3 and 4.
- [ ] Confirm selected destination and instrument/FX chain match the Move.
- [ ] Confirm synth, MIDI FX and audio FX positions/names match the device.
- [ ] Confirm parameter controls reflect metadata and current values.
- [ ] Change one safe test parameter and confirm the Move responds and value refreshes.
- [ ] Test empty slots, missing metadata, disconnects and reconnects.
- [ ] Confirm unsupported/unknown parameters do not become unsafe editable controls.

### E. Master FX
- [ ] Master FX chain is discovered, including empty slots/capacity.
- [ ] Names and slot count match the Move.
- [ ] Selected Master FX parameter metadata and values appear.
- [ ] Change a safe parameter and confirm the physical Move responds.
- [ ] Test no Master FX, unknown/invalid listing and reconnect behaviour.
- [ ] Confirm the UI does not display positions beyond the reported capacity.

### F. Tools and custom UI
- [ ] Load a Tool in Schwung and use Reload/discovery.
- [ ] Confirm Tool identity/state appears even if flat parameter values are absent.
- [ ] If `custom_ui` is advertised, verify the embedded panel loads.
- [ ] Verify the panel stays on the Move host and uses the expected standalone Tool mode.
- [ ] Test a Tool with no custom UI and confirm a clear empty-state message.
- [ ] Check navigation, scrolling, layout, and recovery after Tool unload/reload.
- [ ] Confirm generic Tool values without metadata remain read-only.

### G. Sample Lab, Groove Toolkit and Files
- [ ] Import an audio file into Sample Lab and audition/play it.
- [ ] Verify local sample listing/shelf persists as intended.
- [ ] Do not assume sample transfer to Move; record separately if tested.
- [ ] Edit all three 16-step Groove Toolkit lanes.
- [ ] Export the one-bar MIDI file and verify it opens/plays in a suitable MIDI app/DAW.
- [ ] Open Files, browse/navigate, and verify the expected Schwung file interface and actions.

### H. Stability and reporting
- [ ] Check for stuck loading indicators, stale values or duplicate controls.
- [ ] Disconnect/reconnect during a screen session.
- [ ] Repeat key checks after force-quitting and relaunching.
- [ ] Record actual result and evidence; do not mark untested items as passed.
- [ ] Keep transport play/stop testing separate and non-blocking until the protocol support is established.

## Known pending items

- Physical Move verification of Master FX parameter writes.
- Physical Move verification of Tool custom UI URL and embedded WebKit compatibility.
- Full Mirror validation; prior mirror display attempt was reported as failing.
- Mirror audio behaviour remains untested.
- Transport controls (play/stop and related actions) still need protocol investigation/validation and are not a release blocker for unrelated features.
- Sample transfer from Sample Lab to the Move is not confirmed.
- Full regression pass across the entire checklist is outstanding.

## Per-build notes

The build workflow appends the current commit, branch, run number and build timestamp to this document when uploading the `SchwungPocket-release-notes` artifact. The cumulative history above remains in source control; update it whenever a feature, fix, limitation or test result changes.
