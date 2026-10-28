# macOS Schwung Pocket Test Checklist

**Branch:** `macos-app`  
**Reference branch:** `v0.9-development`  
**Latest verified source commit:** `76484c5`  
**Latest build/package result:** Actions run [#45 passed](https://github.com/chutneyrebel/schwung-pocket/actions/runs/40729549499). Physical app launch, UI behaviour and Move tests are still pending.

Use this checklist when the MacBook and Ableton Move are available. Mark each item as Pass, Fail, or Not tested, and include the build number and Move/Schwung version for any failure.

## A. Launch and layout

- [ ] Download and launch the latest successful macOS artifact from GitHub Actions.
- [ ] Confirm the window opens without a redundant title/header.
- [ ] Resize to a wide window and a narrow window; confirm controls remain usable and the four mixer slots stay readable.
- [ ] Confirm the page scrolls to the bottom and no panel is clipped.
- [ ] Confirm no unexpected blank panels appear for destinations that do not support them.

## B. Section order and collapse persistence

- [ ] Open Settings and move Connection, Mixer, Signal Chain and Modules, Parameter Controls, and Slot Settings up/down.
- [ ] Confirm panels immediately render in the selected order.
- [ ] Quit and relaunch the app; confirm section order is retained.
- [ ] Collapse and expand each panel.
- [ ] Quit and relaunch; confirm each panel's expanded/collapsed state is retained.
- [ ] Switch between Slot, Master FX and Tool destinations; confirm panel ordering remains stable and irrelevant panels do not take up space.

## C. Connection and recovery

- [ ] Connect using the Move's current address.
- [ ] Confirm status changes from Connecting to Connected and shows a useful loading/ready state.
- [ ] Disconnect Wi-Fi or make the Move temporarily unavailable; confirm status is not falsely shown as connected.
- [ ] Restore connectivity and confirm reconnect behaviour.
- [ ] Change the Move address in app settings and confirm the old connection is closed before the new one opens.
- [ ] Reappear/revisit SchwungTroller with the same address and confirm it does not open a duplicate WebSocket.
- [ ] Confirm there is no repeated reconnect loop or duplicated event stream.

## D. Live MIDI activity bridge

- [ ] Open the Move Mirror destination/page used by the app and confirm it loads.
- [ ] Play MIDI notes; confirm the activity indicator turns green and shows MIDI ACTIVE.
- [ ] Stop playing; confirm it returns to yellow and MIDI INACTIVE after approximately 1.5 seconds.
- [ ] Move a MIDI CC control; confirm a CC event appears in the log.
- [ ] Confirm recent activity is deduplicated sensibly and the log remains compact.
- [ ] Collapse and reopen the MIDI Activity log.
- [ ] Navigate away from the mirror page and back; confirm the bridge is installed only once and events continue.
- [ ] If activity does not appear, record the mirror URL/path and whether its visible MIDI log updates. Do not treat a successful compile as proof that the page exposes the expected event surface.

## E. Four-slot mixer

For each of Slots 1–4:

- [ ] Confirm the correct instrument name appears.
- [ ] Move the vertical fader and confirm the displayed percentage updates.
- [ ] Confirm the fader range is 0–400%, with 100% clearly marked.
- [ ] Confirm Mute and Solo controls reflect current Move state.
- [ ] Toggle Mute and Solo; confirm the actual Move state changes and remains correct after refresh.
- [ ] Confirm controls for one slot do not accidentally affect another slot.
- [ ] Confirm unusual or missing volume values do not crash the app or produce NaN/infinite UI values.

## F. Signal chain and module actions

- [ ] Confirm MIDI FX, synth and audio FX appear in the correct positional order.
- [ ] Confirm Install/Swap menus sit beside their respective positions.
- [ ] Swap a module and confirm the displayed name and parameters refresh.
- [ ] Clear a module and confirm its old controls disappear.
- [ ] Test Bypass/Enable separately from Clear.
- [ ] Test empty positions and confirm late metadata does not resurrect removed controls.
- [ ] Confirm chains with different reported capacities are represented without assuming unsupported positions.

## G. Parameter Controls, Master FX and Tool

- [ ] Confirm parameter group selector works when groups are available.
- [ ] Test a numeric parameter and an enum/choice parameter.
- [ ] Confirm read-only or unsupported values cannot be edited.
- [ ] Change destinations and confirm stale parameters from the previous destination disappear.
- [ ] Test Master FX module discovery, swap, clear, bypass and parameter refresh where supported.
- [ ] Test Tool metadata/state display; confirm unsupported Tool values remain read-only.
- [ ] Confirm a missing metadata response produces a clear loading/error/unsupported state instead of a frozen panel.

## H. Slot Settings and regression

- [ ] Test MIDI receive channel and forward channel ranges.
- [ ] Confirm invalid channel values are rejected.
- [ ] Switch repeatedly among Slots 1–4, Master FX and Tool.
- [ ] Test a cold app launch and a Move reconnect.
- [ ] Confirm the app remains responsive while module catalogues and parameter metadata load.

## Build tracking

- Run #45 passed for commit `76484c5`, including the mixer model parity fix and earlier divider fix. Download the artifact associated with this run from [GitHub Actions](https://github.com/chutneyrebel/schwung-pocket/actions/runs/40729549499).
- Runs #39–#42 failed on two compile errors that are fixed in later commits. Run #43 targets an intermediate commit and may remain queued; it does not supersede the successful #45 build.
- Check the [macos-app Actions page](https://github.com/chutneyrebel/schwung-pocket/actions?query=branch%3Amacos-app) for newer commits before downloading.
- Build success validates compilation and packaging only. Sections B–H require runtime testing, and sections D–G require Move verification.
