# Schwung Pocket Release Notes & Regression Guide

> **Purpose:** These cumulative notes ship with every build so testers can re-check existing behaviour, not only the newest change.
>
> **Active development branch:** `v0.9-development`  
> **Source of truth:** `files for chatgpt/SchwungPocket/` and the sibling `files for chatgpt/SchwungPocket.xcodeproj/`.  
> **Safety:** Do not merge or push this work to `main` unless explicitly requested.

## Build status key

- **Implemented:** present in the app source.
- **Build-verified:** compiled and packaged by GitHub Actions. This does not prove device or Move hardware behaviour.
- **Partially tested:** some user/device testing has been reported, but the full matrix has not been completed.
- **Pending hardware verification:** requires testing with the physical Ableton Move running Schwung.
- **Planned / not confirmed:** not to be treated as a working feature.

## v0.9 Code-only integration QA · Stable module picker target

**Build gate:** GitHub Actions #375 passed (commit `7a3510f`) before this QA change.

**What was fixed:** The Add/Swap sheet was formerly created using live `selectedChainComponent` or `selectedMasterFXComponent`, potentially making an outstanding picker follow a later selection. The sheet now captures the original destination and exact chain component as a dedicated intent when opened. Confirming a replacement rechecks the destination and confirmed component membership, refuses a stale operation, and never redirects the request to another position.

**How:** Added `RemoteModulePickerIntent` in `RemoteControlModels.swift`, changed `NativeControlsScreen.swift` to use `.sheet(item:)` rather than a global Boolean, and consolidated picker entrypoints for slot and Master FX chains. `ModuleSwapSheet` receives its immutable target and validates it at selection/confirmation time. The existing `RemoteControlStore.swapModule` and `swapMasterFXModule` methods, catalog discovery, and protocol payloads were not altered. Regression tests cover target identity, slot change, loss of confirmed membership, and separate Master FX addressing.

**Why:** A delayed or interrupted module-picking workflow must not silently mutate a different slot or a different chain position. Keeping the original target fixed is safer and more predictable, especially when remote data refreshes asynchronously.

**Files:** `NativeControlsScreen.swift`, `RemoteControlModels.swift`, `tests/RemoteControlRegression.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limits:** This prevents stale destination/section retargeting but does not yet compare a changed module revision or name against the initial module state. That is a future optimistic-concurrency concern requiring appropriate stable metadata. Live replacement and recovery remain unverified on Move.

**Testing decision:** GitHub Actions regression, syntax, Xcode build and packaging; no standalone hardware test. Deferred consolidated Phases 1–5 and M1.18–M1.24 tests remain intact. No merge to main.

## v0.9 Code-only integration QA · Chain certainty and safe Clear

**Build gate:** GitHub Actions #374 passed on commit `4c83634` before this QA batch.

**What was fixed:** A connected Schwung socket does not prove every signal-chain section has been reported. The UI previously represented a missing module name as EMPTY and offered Add even when `slot_info` explicitly marked that MIDI FX / Instrument / Audio FX section unknown. It now distinguishes OFFLINE, CHECKING, EMPTY, ACTIVE and BYPASSED, only advertising empty-position Add once the owning section's membership is confirmed. This applies to slot chains and Master FX. A separate destructive-action risk existed because the old Clear dialog read the currently selected chain component at confirmation time. Clear now captures its original slot destination and component key; it refuses the write if destination has changed, rather than targeting a different position.

**How:** Added a pure `RemoteChainPositionPresentation` policy and `RemoteSlotClearIntent` identity guard in `RemoteControlModels.swift`. `RemoteControlStore.isChainMembershipConfirmed` exposes the existing internal `confirmedChainSections` without creating new subscriptions or protocol commands. `NativeControlsScreen.swift` now uses this policy for status text, Add availability and accessibility, and uses a captured confirmation intent for slot module deletion. Tests cover connection/metadata combinations and stable destructive intent identity.

**Why:** Never present unknown remote state as established truth or permit a destructive action to drift to a different slot/component while a confirmation is open. This is a correctness and safety improvement, not a visual redesign.

**Affected files:** `RemoteControlModels.swift`, `RemoteControlStore.swift`, `NativeControlsScreen.swift`, `tests/RemoteControlRegression.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limits:** True bypass status still depends on device state received through Schwung; the app does not invent missing flags. Master FX and Tool commands are unchanged. Physical behavior, particularly partial metadata updates after swaps and reconnects, remains pending the user's deferred combined hardware session.

**Verification:** Run automated Swift syntax, remote regression and iOS build. No hardware test requested. Do not merge to `main`.

## v0.9 Hybrid Workspace · Signal Chain interaction design

**Build gate:** Build #373 for commit `ccccab3` passed prior to these changes.

**What:** Signal Chain now groups components into three readable stages: MIDI FX, Instrument and Audio FX, with directional flow markers between stages. Position counts come from the existing reported capacities (and legacy fallbacks), not a newly assumed fixed chain. Each card clearly indicates EDIT PARAMETERS or ADD MODULE as its primary action. The selected position is shown beside the contextual Add/Swap control. Master FX has distinct stage guidance, explicit active/bypassed/empty/offline status, and an Add/Swap label based on the selected position.

**How:** Introduced a presentation-only `SignalChainStage` enum and `chainComponents(in:)` filter in `NativeControlsScreen.swift`. Existing individual component IDs, `RemoteControlStore` metadata, selection handlers, `ModuleSwapSheet`, bypass, and destructive clear behavior are unchanged. Reorganized the SwiftUI card grid into stage groups while keeping the existing two-column layout for each group. Master FX status reuses the same connection-aware label helper as slot components.

**Why:** A signal chain should convey order of operations, not look like an unstructured list. Explicit primary actions distinguish navigating to parameters from bypassing or removing a module. They also reduce ambiguity for empty positions and Master FX.

**Files:** `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limitations:** Stage group appearance and accessibility still need device-width verification. Module picker compatibility, Master FX commands and actual on-Move effects are unverified in this pass. The status helper currently treats connected missing module names as empty; unknown partial metadata still requires separate confidence handling before release. No change to remote protocol, mixer, parameter writes, or DSP.

**Verification:** GitHub Actions regression, Swift syntax, Xcode project inspection and unsigned iOS build. Physical testing is deferred at user request and remains part of the next combined Phases 1–5/M1.18–M1.24 test. No merge to main.

## v0.9 Hybrid Workspace · Creative workflow shortcuts

**Build gate:** Build #372 from `423a6d4` was still running when this change began; earlier syntax and regression stages had passed. This entry records new work independently of that build's final outcome.

**What:** Chain and Design now offer a compact, explicitly highlighted Slot 1–4 shortcut row. Design also offers a contextual Add or Swap action for the currently selected instrument, MIDI FX, audio FX or Master FX position. Users no longer need to return to Perform to change slots, or return to Chain simply to open the installed module picker.

**How:** Added `workspaceSlotStrip` and `designModuleActions` in `NativeControlsScreen.swift`. Shortcut taps call the existing `selectWorkspaceDestination` handler, which preserves per-slot editing context and invokes the same `RemoteControlStore.select` behavior as the Performance mixer destination selector. Add/Swap invokes the existing `openModulePicker(for:)` or Master FX `ModuleSwapSheet` flow and is unavailable when disconnected. No new protocol messages, inferred device states, parameter writes or mixer controls.

**Why:** Minimize navigation hops between four slots and the currently edited component, while maintaining clear selection context and familiar module actions.

**Files:** `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limitations:** Slot strip intentionally shows slots only; the global Master FX and Tool destinations are still accessed through the Performance destination selector. Add/Swap merely opens existing module discovery, so compatibility and actual replacement remain subject to the postponed hardware regression. Layout has not been verified on a physical iPhone.

**Verification and next step:** Run deterministic regressions, Swift validation, Xcode inspection and unsigned iPhone build in Actions. Hardware tests remain deferred by user request and bundled with the consolidated v0.9 testing phase. Continue visual consistency or remaining QA work after CI; do not merge `main`.

## v0.9 Hybrid Workspace · Visual polish (navigation and control density)

**Build gate:** Build #371 for commit `2436b63` passed before visual refinements began.

**What:** Replaced the default segmented control with a compact three-way switcher featuring distinct icons, persistent text labels, stronger selected-state borders and equal tap targets. Added a descriptive hierarchy to Chain/Design context headers so the selected destination, module and editing role are easier to distinguish. Shortened the Performance summary heading, strengthened the highlighted parameter-group state and adjusted the knob layout calculation to make better use of compact view widths. Reduced outer horizontal padding slightly to improve iPhone portrait space.

**How:** These are view-local changes in `NativeControlsScreen.swift`: the switcher still reads the saved workspace order, updates the same `workspace` state and does not invoke network subscriptions. Header text is derived from existing selected component and live module metadata. The knob grid still uses the existing width measurement and `RemoteParameterLayout.groups` ordering, only recalculating how many columns fit. The rotary control gesture and wire write path are unchanged.

**Why:** A three-way creative workspace needs easy-to-recognize navigation, consistent selection feedback, readable context and efficient use of limited screen width. This improves usability without changing device behavior or inventing new protocol support.

**Files:** `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limitations:** The narrower knob-grid columns may need adjustment for unusually long value labels or large Dynamic Type; actual rendering on iPhone has not yet been inspected. Some module pages can still use existing custom/web UI and existing legacy visual styling. No claims of physical behavior verification.

**Testing:** Run Swift syntax, model regression and unsigned iOS build CI. The complete Phases 1–5/M1.18–M1.24 hardware and offline visual matrix remains deferred at the user's request. No separate hardware test is necessary now, and `main` remains untouched.

## v0.9 Hybrid Workspace · Integrated UI polish (workspace preferences)

**What changed:** Replaced Settings' obsolete single-page SchwungTroller section-order controls with reordering for the three actual Perform / Chain / Design views and a preferred starting workspace. The workspace switcher immediately reflects the saved order. The starting view is applied once per mounted SchwungTroller session so returning from Mirror does not unexpectedly reset user navigation. The existing Slot Settings disclosure preference remains intact.

**How:** `ContentView.swift` now stores `SchwungPocket.TrollerWorkspaceOrder.v1` and `SchwungPocket.TrollerInitialWorkspace.v1` rather than exposing the inactive old section order. `NativeControlsScreen.swift` consumes the same keys; its old unused section-order view helpers are retired. A shared, pure `RemoteWorkspacePreferences` policy in `RemoteControlModels.swift` validates, deduplicates and completes order strings, protects against invalid starting views and safely processes reorder actions. Regression tests verify defaults, malformed legacy-like preferences, reordering and bounds.

**Why:** Settings must control real behavior. The previous section-order UI wrote a stored preference that the new three-view layout no longer read, misleading users into thinking the screen changed. This preserves meaningful customization without interfering with Schwung's live state.

**Affected files:** `files for chatgpt/SchwungPocket/ContentView.swift`, `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `files for chatgpt/SchwungPocket/RemoteControlModels.swift`, `tests/RemoteControlRegression.swift`, `RELEASE_NOTES.md` and `docs/v0.9-development-test-matrix.md`.

**Compatibility:** Legacy `SchwungPocket.TrollerSectionOrder.v1` data is left untouched but is no longer surfaced: old sections have no one-to-one mapping into three independent views. Existing users receive the default workspace order; old collapsed Slot Settings preferences remain functional. No API, mixer, module or parameter-write changes.

**Testing decision:** User deferred physical testing. No hardware checks are requested now. CI compilation, Swift syntax and model regressions are required, with a future consolidated visual/hardware pass checking stored preferences, slot/parameter restoration and all previously deferred M1.18–M1.24 scenarios. Continue UI refinement after successful CI without changing `main`.

## v0.9 Hybrid Workspace · Phase 5 (integrated workspace QA)

**Build gate:** Build #369, commit `20c9aca`, completed successfully before this phase.

**What was corrected:** In the prior hybrid workspace, switching between instrument slots reset the selected chain component to Instrument, and the Performance View's Design shortcut also reset it. Parameter-group selection was global to the active editor and could not recall a group after a slot switch. The integrated workspace now remembers a selected component per destination, preserves that selection when using Perform's Design shortcut, and remembers instrument hierarchy page selection per slot and confirmed instrument identity.

**How:** Added view-local component and page selection helpers in `NativeControlsScreen.swift`. Slot selector buttons, Signal Chain cards and the Design component picker now share the same selection handler. Instrument page chips and the long-hierarchy picker save the requested page under a slot-plus-instrument key. When fresh hierarchy metadata arrives, restoration occurs only if Schwung still reports the saved page. Added a small, testable `RemoteWorkspaceContextPolicy` in `RemoteControlModels.swift` and regression checks for separate slots, unknown identity, missing metadata and removed pages. Device live values and WebSocket ownership remain exclusively in `RemoteControlStore`.

**Why:** Perform, Chain and Design must refer to the same sound-design context rather than silently reverting to the instrument whenever a user changes views or slots. Validating restoration against *fresh* hierarchy metadata prevents obsolete page references from being presented as working device controls.

**Affected files:** `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `files for chatgpt/SchwungPocket/RemoteControlModels.swift`, `tests/RemoteControlRegression.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Scope/limitations:** Restoration is session-local and does not persist across application relaunches. Page memory is for instrument hierarchy groups, not FX-specific custom web panels. A module occupying a different position or a renamed module is treated as a distinct context. The old section-order preferences still need adaptation for the new dedicated workspace views. CI validates the code but not physical Move behavior.

**Next action and test decision:** Confirm CI and perform optional no-Move navigation/visual QA. No immediate hardware test is necessary for this presentation-state change; **one consolidated iPhone + Move hardware regression is recommended before calling v0.9 release-ready**, covering all Phase 1–5 flows and M1.18–M1.24 synchronization changes. No merge to main.

## v0.9 Hybrid Workspace · Phase 4 (Parameter Studio)

**What:** Parameter Studio now offers direct switching between reported MIDI FX, instrument and audio FX positions, plus a Master FX position selector where appropriate. Instrument groups with eight or fewer hierarchy levels are shown as horizontally scrollable one-tap page chips; larger hierarchies retain a dropdown. Numeric knob grids respond to their actual available width, targeting four compact portrait controls and up to eight controls on wide layouts. The parameter card labels Master FX correctly.

**How:** Added view-local SwiftUI component pickers and quick page buttons in `NativeControlsScreen.swift`. Both use the existing selected component and `RemoteControlStore.selectedLevelID`; no network subscriptions or new parameter write logic. The grid measures its card content width with `GeometryReader` and uses flexible columns. Existing `RemoteParameterLayout.groups` continues to preserve Schwung's declared order and non-knob controls.

**Why:** Users should move between module sound-design controls without returning to Chain, and large instrument hierarchies should be navigable with one tap. Responsive layout should reflect the available editing surface, not assume a specific device model.

**Files:** `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limitations:** Changing slots still resets the selected component to Instrument; full per-module/per-slot group restoration needs a dedicated state ownership pass. Displaying four compact knobs depends on the real card width and accessibility text sizes; layout must be checked on an iPhone. Module-specific custom UI parity remains dependent on the existing Schwung-provided URL/metadata. No claim of Move hardware validation.

**Verification:** CI syntax/regressions/iOS packaging plus optional offline visual navigation and portrait/landscape checks. **A hardware test is not necessary to proceed to integrated workspace QA.** A combined physical test is advised before the v0.9 release candidate to validate parameter writes, module changes and reconnection after M1.18–M1.24.

## v0.9 Hybrid Workspace · Phase 3 (Signal Chain)

**What:** Selecting a loaded MIDI FX, instrument, audio FX or Master FX now opens the corresponding Design view. Selecting an empty position when connected opens the existing compatible module picker. The slot toolbar identifies the action as Add or Swap based on reported membership. Disconnected positions show OFFLINE / Waiting for Move rather than being described as confirmed empty. The main module buttons have accessible actions; Bypass/Enable and destructive Clear remain separate.

**How:** Existing Signal Chain SwiftUI cards now route through workspace selection and existing `ModuleSwapSheet` operations. No new server commands, subscriptions or audio write paths were added. Module status derives from existing `RemoteControlStore` connection and chain names.

**Why:** Make the Chain view a fast routing-and-selection workspace. Empty positions should offer a useful action; live components should be one tap from sound design. Offline UI must avoid misleading claims about Move state.

**Files:** `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limitations:** The slot chain is still shown using the existing two-column cards rather than a new flow diagram. Deep parameter-group restoration is Phase 4. Existing Master FX module replacement and picker compatibility remain subject to physical testing. This change only guards disconnected empty-state wording; temporarily unknown sections while connected may still require explicit confidence indicators in a later iteration.

**Testing recommendation:** Automated compile/regression first; optional no-Move navigation inspection. A hardware test is **not necessary to continue Phase 4**, but the combined iPhone + Move validation must include loaded and empty positions and Master FX behavior before release.

## v0.9 Hybrid Workspace · Phase 2 (Performance View)

**What changed:** Performance View now has a compact single connection/MIDI status card with Connect/Disconnect, Reload and expandable MIDI activity, the existing four-slot mixer, and a selected-destination focus card with direct Signal Chain and Design shortcuts. Tool destinations open their read-only state in Design. Removed the duplicate chain navigation button in favor of contextual actions.

**How:** Added presentation-only SwiftUI helpers in `NativeControlsScreen.swift` using the existing `RemoteControlStore` and `MirrorMIDIActivityStore`. The underlying four vertical faders, 0–400% scaling, M/S controls, wire messages, and remote subscription lifecycle remain unchanged. The selected destination's name is derived from confirmed displayed metadata, not a placeholder module.

**Why:** Move session essentials belong above the fold: connection, four faders and a direct path from mixing to sound design. This improves navigation without more protocol complexity or rediscovering module metadata each time a view switches.

**Files:** `files for chatgpt/SchwungPocket/NativeControlsScreen.swift`, `RELEASE_NOTES.md`, `docs/v0.9-development-test-matrix.md`.

**Limitations and next work:** UI is not yet evaluated on an actual narrow iPhone viewport; Chain and Design visual refinements are Phase 3/4. Old settings for section ordering require adapting to the new hybrid workspace. Recent connection/parameter reliability fixes still require a combined physical Move regression before release.

**Verification:** Syntax, deterministic regression and unsigned iOS build are automated in GitHub Actions. **Hardware test not required to continue Phase 3.** Optional offline visual check: open Perform, inspect four faders/connection indicator, show/hide MIDI log, select slots, and follow Chain/Design shortcuts; report clipping or overlap. Do not mark live playback and hardware behavior passed based on CI.

## v0.9 Hybrid Workspace · Phase 1 (navigation foundation)

**What changed:** Replaced the single long SchwungTroller page with three equal workspace destinations: Perform, Chain and Design. Perform holds the connection, four-slot mixer and slot settings. Chain reuses the existing slot or Master FX module cards. Design reuses the existing parameter hierarchy and editor. Selecting an occupied slot-chain module directly opens Design, while empty positions remain on Chain for module management.

**How:** Added a view-local segmented workspace selection and context header in `NativeControlsScreen.swift`. The three views reuse existing card views and retain one `RemoteControlStore`. Switching workspace does not invoke `remote.select`, reconnect or subscribe; selecting a slot still uses the existing destination selector in Perform.

**Why:** Live mixing and detailed sound design should be equally accessible without scrolling through unrelated cards. Reusing the existing control bindings minimizes regressions and avoids introducing speculative protocol messages.

**Known limits:** The selected module defaults to Instrument when the user changes destination, as in the previous UI. Deep per-slot module and parameter-group restoration are subsequent steps. Section-order Settings currently refers to the legacy stacked layout and will require adaptation to the new three-view workspace.

**Verification:** CI can verify Swift syntax, regression tests and IPA packaging. A no-Move visual test is appropriate for view switching, module-to-Design navigation and presentation. A hardware test is **not required to continue Phase 2** because this phase adds no new wire messages; combined hardware regression remains necessary before shipping v0.9.

## M1.24: Reconcile parameter definitions after module refresh

- When a current module re-advertises changed or removed parameter definitions, retires the old cached value, last-sent value, editing gesture, unconfirmed echo and queued continuous writes for those exact wire keys.
- Leaves unchanged parameter definitions and their active values/gestures alone. New definitions do not discard parameter values that arrived ahead of metadata.
- Applies to both normal chain components and Master FX, without introducing guessed Schwung protocol messages.
- Retires writes by exact parameter key, preserving similarly named controls such as `cutoff2` when `cutoff` is updated.
- Adds deterministic regression cases for changed ranges, removed controls, identical rebroadcasts and initial discovery.
- **Status:** implemented on development branch; GitHub Actions and physical Move test remain separate verification gates.

## M1.23: Partial chain listing recovery

- Tracks confirmed module-chain sections independently: synth, MIDI FX, audio FX, and Master FX.
- A partial `slot_info` (or a section temporarily marked unknown) cannot wrongly declare every missing position empty. Late-arriving metadata is allowed until that particular section has a trustworthy listing.
- Once a section has been confirmed, its empty positions remain protected from orphaned metadata and values, including through subsequent temporary unknown responses.
- Missing `synth` data is not treated as an authoritative empty instrument.
- Adds deterministic tests for partial listing transitions, confirmed empty positions, Master FX, and component classification.
- **Status:** source committed; CI and hardware checkpoint tracked separately.

## M1.22: Verify parameter ownership before sending

- Guards begin-edit, end-edit and parameter writes against the *current full parameter definition* rather than merely its wire key. A stale knob or enum callback cannot write with obsolete ranges or options when another module reuses its key.
- Does not modify the on-wire Schwung protocol or the existing mixer and slot-setting write paths.
- Regression tests cover overlapping effect keys, current parameters, removed controls and changed Master FX choices.
- **Upstream limitation:** Schwung Manager's `wsChainParams` message has `type`, `slot`, `component`, `data`, but no module revision/response request ID; indistinguishable metadata from two identically described modules cannot be reliably disambiguated by this client alone.
- **Status:** committed to v0.9 development; build and hardware checks tracked separately.

## M1.21: Guard orphaned module metadata

- After Schwung has supplied a chain listing, late `chain_params` responses for unoccupied synth, MIDI FX, audio FX or Master FX positions no longer repopulate the parameter editor.
- Late module parameter-value updates from those empty positions are filtered by component identity.
- Preserves initial discovery compatibility when metadata arrives before the first authoritative chain listing.
- Slot mixer state is intentionally exempt from module gating; unknown keys are not guessed into effect components.
- Regression tests cover occupied/empty components, MIDI FX, Master FX key parsing and initial-discovery behavior.
- **Limit:** Schwung's current messages do not carry a request ID or module revision. A delayed response for a *replaced but still occupied* position cannot be conclusively attributed to the old module from key/slot alone. This change specifically prevents orphan metadata, not all same-position races.
- **Status:** source committed; GitHub Actions and hardware validation tracked separately.

## M1.20: Full parameter cleanup on hardware-driven FX changes

- Uses a shared deterministic change detector for slot and Master FX chain listings; unchanged device rebroadcasts do not reset controls.
- When a Master FX module is changed or removed directly on Move, the native editor now clears old parameter metadata, values, editing gestures, unconfirmed echoes, custom UI references and unsent continuous writes for only that affected FX position.
- Keeps the other Master FX positions and their current parameter state intact.
- Added deterministic tests for unchanged listings, replacement, addition, removal, and isolation from unrelated instruments.
- **Status:** implementation committed to v0.9; live device behavior awaits the combined hardware test checkpoint.

## Master FX asynchronous load safety

- Resolved a race where a delayed installed-module DSP-path lookup could load an effect after its position had been cleared or replaced.
- Tracks each Master FX position's pending lookup independently. New swaps and clears cancel prior lookups for that position without disrupting another position.
- Rejects stale HTTP completions after destination switches, disconnects, address changes, or socket replacement; stale requests cannot report errors over newer actions.
- Added deterministic coverage for superseded module choices, clearing, connection/editor generations, cancellation and destination changes.
- **Status:** implemented and sent through GitHub Actions; on-device Master FX swaps still require the next hardware checkpoint.

## Latest v0.9 reliability checkpoint

### Module catalogue request ownership
- Cancels superseded HTTP module-discovery tasks even when an existing cache can be reused immediately.
- Clears an old Move's installed-module list when the address changes, so a new or failed lookup cannot offer modules from the wrong device.
- Guards responses and loading-state cleanup with a request generation. An old request can no longer stop the spinner or overwrite the latest Move's module list.
- Added deterministic regression checks for current, superseded and cancelled catalogue lookups.
- **Status:** GitHub Actions #358 build-verified; live Move address switching still requires hardware verification.

## New additions in the current development line

### Instrument and FX hot-swapping
- Added installed-module discovery using Schwung's `/api/slot-modules` endpoint.
- Added a Swap action for the currently selected synth, MIDI FX, audio FX or Master FX position.
- The picker filters modules by compatible chain position and excludes modules marked as device-only.
- A confirmation step appears before replacing a loaded module.
- Slot-chain writes use Schwung's `set_param` protocol with keys such as `synth:module`, `midi_fx1:module` and `fx1:module`; Master FX uses `set_master_fx_param` with the selected effect's discovered DSP path.
- **Status:** implemented in source; requires a successful build and physical Move verification. Older Schwung builds without the module-list endpoint will show an explanatory error rather than guess module IDs.

### Per-slot mute and solo
- Added M and S toggle buttons inside each of the four Slot destination tiles.
- The app subscribes to all four slot mixer states so each tile can reflect the Move's reported mute/solo state while the detailed controls remain focused on one destination.
- Toggles send the existing `set_param` keys `slot:muted` and `slot:soloed` to the corresponding wire slot.
- Controls are disabled while the remote connection is down.
- **Status:** implemented in source; actual mixer response and state synchronisation require physical Move verification.

### Tool status visibility
- Added a Tool status card to show the detected Tool ID, whether Schwung advertised a custom web panel, and any flat Tool state values that were received.
- Repeated Tool discovery messages no longer clear already received state when the Tool ID has not changed.
- **Status:** improved diagnostics and state handling implemented; the user's reported `drums practice` Tool still requires a targeted hardware retest to confirm the missing information is resolved.

### Tool custom Web UI panel
- Added handling for Schwung's `custom_ui` message for the Tool target, including the advertised component and URL.
- Added an embedded WebKit panel for a supported Tool custom UI URL.
- The resolver attempts to keep the embedded UI on the same Move host and port, uses the Move connection's base scheme, and adds standalone Tool query parameters.
- Added empty-state messaging for Tools that expose neither flat parameter values nor a custom web UI.
- **Status:** build-verified on commit `365bb7faa48c1e6df532f154e4f743f785c86ef2` (GitHub Actions run `40318579760` passed syntax validation, iOS build and artifact packaging). Physical Move verification of the custom UI is still pending.

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
- **Known limitation:** an earlier Android 4.4.4 browser/mirror attempt displayed mostly text. The user has now confirmed Mirror audio works. Continue to regression-test the iPhone mirror's display, scaling and interaction separately.

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
- **Status:** user has confirmed Master FX works on their Move. Re-test discovery, values and parameter writes during regression testing.

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
- GitHub Actions builds on pushes to `v0.8.3-development` and `v0.9-development`, manual workflow dispatch, and pull requests targeting `main`.
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
- Latest full build/package verification: commit `365bb7faa48c1e6df532f154e4f743f785c86ef2`, GitHub Actions run `40318579760` passed and uploaded the unsigned IPA, build log and cumulative release notes. This confirms compilation and packaging only, not physical Move behaviour.

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

### F. Slot mixer and hot-swap
- [ ] Confirm M/S toggles appear inside Slot 1, Slot 2, Slot 3 and Slot 4 tiles.
- [ ] Toggle mute and solo for each slot and confirm the physical Move responds.
- [ ] Change mute/solo on the Move and confirm the four app tiles update.
- [ ] Open Swap for the synth, a MIDI FX position and an audio FX position.
- [ ] Confirm the picker lists installed modules of the correct type and excludes device-only modules.
- [ ] Confirm the replacement prompt appears before the write.
- [ ] Swap one test module, confirm the chain name changes, and verify the new parameters are loaded.
- [ ] Test unavailable module endpoint, failed load and an empty FX position without leaving stale controls.

### G. Tools and custom UI
- [ ] Load the `drums practice` Tool in Schwung and select Tool in SchwungTroller.
- [ ] Confirm Tool identity/status appears even if flat parameter values are absent.
- [ ] If `custom_ui` is advertised, verify the embedded panel loads and is interactive.
- [ ] Verify the panel stays on the Move host and uses the expected standalone Tool mode.
- [ ] Test a Tool with no custom UI and confirm a clear empty-state message.
- [ ] Check navigation, scrolling, layout, and recovery after Tool unload/reload.
- [ ] Confirm generic Tool values without metadata remain read-only.

### H. Sample Lab, Groove Toolkit and Files
- [ ] Import an audio file into Sample Lab and audition/play it.
- [ ] Verify local sample listing/shelf persists as intended.
- [ ] Do not assume sample transfer to Move; record separately if tested.
- [ ] Edit all three 16-step Groove Toolkit lanes.
- [ ] Export the one-bar MIDI file and verify it opens/plays in a suitable MIDI app/DAW.
- [ ] Open Files, browse/navigate, and verify the expected Schwung file interface and actions.

### I. Stability and reporting
- [ ] Check for stuck loading indicators, stale values or duplicate controls.
- [ ] Disconnect/reconnect during a screen session.
- [ ] Repeat key checks after force-quitting and relaunching.
- [ ] Record actual result and evidence; do not mark untested items as passed.
- [ ] Keep transport play/stop testing separate and non-blocking until the protocol support is established.

## Known pending items

- Physical Move regression of Master FX parameter writes after recent changes, despite the user's confirmation that Master FX works.
- Physical Move verification of instrument/FX hot-swapping and M/S mixer controls.
- Tool discovery/UI still needs a targeted retest with the user's `drums practice` Tool.
- Physical Move verification that the `drums practice` Tool identity, state and custom UI appear correctly.
- Full Mirror display/scaling validation. Mirror audio has been confirmed working by the user.
- Transport protocol investigation completed: Schwung Manager's Remote UI WebSocket handler accepts subscription, parameter-write, hierarchy and Tool/Master FX messages, but exposes no global Move play/stop command. The Overtake Tool's transport state feed is Tool-specific and does not provide global transport control. Do not add speculative play/stop messages. Revisit only if Schwung exposes a documented control path.
- Master FX hot-swap remains unresolved: the legacy DSP-path fallback removes the error but has not been confirmed to replace the effect on the Move. Deferred to the v1.0 roadmap; do not treat as fixed in v0.8.3.
- Sample transfer from Sample Lab to the Move is not confirmed.
- Full regression pass across the entire checklist is outstanding.

## Per-build notes

### v0.9 follow-up · Breakbeat parameters and screen layout
- Breakbeat `filepath` metadata now explains that the A Sample WAV picker is Move-side and is not editable in the native parameter panel yet; it is no longer described as a generic unsupported file path.
- Breakbeat `canvas` metadata now identifies the Status item as a module-authored `status_view.js` screen and explicitly clarifies that the message is informational, not a connection error. No guessed writes are sent.
- Removed the large SchwungTroller hero header and subtitle from the Performance screen. Connection & MIDI Activity now appears first, followed by performance status and the mixer.
- **Testing note:** a native Breakbeat sample picker and rendering of the custom canvas UI are still separate feature work; this change improves handling and explanation rather than claiming those controls are implemented.

### v0.9 carry-forward · reliability and module discovery
- **Active branch:** `v0.9-development`. Selected fixes from the completed v0.8.3 pass are carried forward while preserving the v0.9 SchwungTroller redesign and accessibility refinements.
- **Previously user-verified:** page/tab switching no longer incurs the old multi-second delay (Build #312, commit `f0ffa12475683cfbc866e879f998e568eb1821bd`). The v0.9 persistent SchwungTroller/navigation work remains intact.
- Hot-swap picker groups installed compatible modules by Schwung catalogue subcategory and sorts categories then module names.
- Catalogue subcategories survive merging catalogue and installed-module endpoint data.
- Parameter metadata uses Schwung's `label` when `name` is absent, without guessing parameter control types.
- Canvas controls without explicit options and Move-side filepath parameters remain read-only with clearer explanations; explicit canvas options remain choice controls.
- **Still deferred:** new Master FX Clear, Tool Clear and transport controls. Build success will not count as physical Move runtime verification until tested on device.

The build workflow appends the current commit, branch, run number and build timestamp to this document when uploading the `SchwungPocket-release-notes` artifact. The cumulative history above remains in source control; update it whenever a feature, fix, limitation or test result changes.

### v0.9 follow-up · Remove duplicate connection status
- Removed the redundant performance status strip that repeated connection state already shown in the Connection & MIDI Activity card.
- Kept the primary Connection & MIDI Activity section at the top; the performance mixer follows it directly, avoiding two separate connected/status panels.
- **Testing note:** confirm the page shows one connection section only and that Connect/Disconnect, Reload, MIDI activity and destination selection remain available.

### v0.9 follow-up · Breakbeat filepath metadata
- Replaced the Breakbeat-specific filepath warning with a generic explanation that file paths require the Move-side browser and are not normal editable parameters.
- When Schwung supplies `root` and `filter` metadata, SchwungTroller now displays the reported folder and accepted file types beside the read-only explanation. This is informational only; it does not guess or send a path write.
- Protocol investigation found no documented file-browse/list action in the current Remote UI WebSocket messages. A native in-app picker remains blocked until Schwung exposes a supported browsing route or a compatible module UI can be embedded.
- **Testing note:** confirm Breakbeat's A/B sample paths remain read-only, the reported folder/filter are shown when present, and ordinary numeric/choice parameters still work.
