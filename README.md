# Schwung Pocket v0.8.2: Modular Native Controls

Schwung Pocket is an iPhone companion for an Ableton Move running Schwung.

## v0.8.2

- **Experimental Studio is gone.** Native Controls, Sample Lab and Groove Toolkit are now separate cards in the Modules tab, each opening its own screen. Modules are registered in `PocketStudioModule` (`StudioModules.swift`); adding one means adding a case, not touching navigation.
- **Destination selector.** The slot stepper is replaced by six tappable boxes: Slot 1-4, Master FX, Tool. The destination is modelled as `RemoteDestination`, not an integer.
- **Automatic refresh.** Changing destination keeps the WebSocket open, sends `subscribe` for the new slot, clears the old controls (shown as loading), and ignores any message whose `slot` is not the current one. Dropped connections retry with exponential backoff (up to 6 attempts); the socket is closed when the screen disappears or the app backgrounds and reopened on return.
- **Rotary knobs.** `RotaryKnob` is a reusable SwiftUI control (drag, step snapping, clamping, VoiceOver adjustable). Float/int parameters use knobs; enums use segmented/menu pickers; everything else is read-only.
- **`unsupported control type: init`.** Unknown and `init` parameters now render as read-only rows with their raw definition, and nothing is ever sent for them. See "Unverified" below.
- **Developer diagnostics** toggle on the Native Controls screen logs parameter metadata (keys, types, ranges, raw definition) via `os.Logger` and can copy the metadata to the clipboard. The Move address is never logged.

Architecture: `RemoteControlModels.swift` (protocol adapter + parameter model), `RemoteControlStore.swift` (all socket/state logic), `RotaryKnob.swift`, `NativeControlsScreen.swift`, `StudioModules.swift`.

## Unverified (not tested against hardware)

- **Master FX and Tool:** no verified Remote UI addressing exists, so they show a "not available yet" state and send nothing. Capture the Manager's WebSocket traffic for them and update `RemoteProtocolAdapter`.
- **Slot numbering:** Slot N is sent as wire `slot: N`, matching v0.8.1. If Slot 1 turns out to be wire 0, change `RemoteProtocolAdapter.slotWireOffset`.
- **Unsubscribe:** none is sent (none was observed). Late messages are filtered client-side.
- **`init` parameters:** the actual metadata for the `9w9` instrument was not available while building this release, so the `init` handling is deliberately conservative (read-only + raw definition). Turn on diagnostics, open the `9w9` slot, copy the metadata and use it to decide whether `init` should become editable.
- **Enum serialization:** sent as the option index (unchanged from v0.8.1).

## Build through GitHub Actions

Replace the root-level `SchwungPocket-Starter.zip` in the existing repository with this archive, keeping the exact filename. Leave `.github/workflows/build-ipa.yml` unchanged and rerun the existing workflow.

## Validation notes

Checked here: ZIP integrity, `project.pbxproj` structure and file registration, `Info.plist` parse, and a bracket-balance scan of all Swift files. **Not** checked: Swift compilation, an Xcode build, unit tests, or any device. This environment has no Swift toolchain or iOS SDK, so treat v0.8.2 as unbuilt until the GitHub Actions run succeeds.
