import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func makeParameter(_ name: String, type: String) -> RemoteParameter {
    let item: [String: Any] = [
        "key": name, "name": name, "type": type,
        "min": 0, "max": 1, "options": ["Off", "On"]
    ]
    guard let parameter = RemoteParameter.parse(item, component: "synth") else {
        fatalError("Could not construct regression fixture")
    }
    return parameter
}

@main
struct RemoteControlRegression {
    static func main() {
        // Rapid fader/knob updates replace unsent samples for the same key.
        var queue = RemoteOutboundQueue()
        queue.enqueue("vol=1", coalescingKey: "set_param:0:slot:volume")
        queue.enqueue("vol=2", coalescingKey: "set_param:0:slot:volume")
        check(queue.count == 1, "continuous writes should coalesce")
        check(queue.dequeue()?.text == "vol=2", "latest unsent value should win")
        check(queue.isEmpty, "queue should drain")

        // A structural command is a barrier. Both adjacent values must survive.
        queue.enqueue("before", coalescingKey: "set_param:0:synth:cutoff")
        queue.enqueue("swap", coalescingKey: nil)
        queue.enqueue("after", coalescingKey: "set_param:0:synth:cutoff")
        check(queue.count == 3, "module swap must fence parameter updates")
        check(queue.dequeue()?.text == "before", "preserve pre-swap write")
        check(queue.dequeue()?.text == "swap", "preserve structural operation order")
        check(queue.dequeue()?.text == "after", "preserve post-swap write")

        // Writes for different slots or parameters must never overwrite each other.
        queue.enqueue("slot0", coalescingKey: "set_param:0:slot:volume")
        queue.enqueue("slot1", coalescingKey: "set_param:1:slot:volume")
        queue.enqueue("filter", coalescingKey: "set_param:0:synth:filter")
        queue.enqueue("slot0-new", coalescingKey: "set_param:0:slot:volume")
        check(queue.count == 3, "unrelated writes must survive coalescing")
        check(queue.dequeue()?.text == "slot1", "unrelated writes retain order")
        check(queue.dequeue()?.text == "filter", "second key retains order")
        check(queue.dequeue()?.text == "slot0-new", "newest write appended after others")

        queue.enqueue("stale", coalescingKey: nil)
        queue.clear()
        check(queue.isEmpty, "disconnect clears pending commands")

        let controls = [
            makeParameter("cutoff", type: "float"),
            makeParameter("resonance", type: "float"),
            makeParameter("mode", type: "enum"),
            makeParameter("drive", type: "float"),
            makeParameter("status", type: "init"),
            makeParameter("level", type: "float")
        ]
        let groups = RemoteParameterLayout.groups(controls)
        check(groups.map(\.count) == [2, 1, 1, 1, 1], "interleaved page controls should form ordered groups")
        check(groups.flatMap { $0 }.map(\.key) == controls.map(\.key), "layout must preserve device parameter order")
        check(RemoteParameterLayout.groups([]).isEmpty, "empty pages stay empty")
        // The root hierarchy declares navigation order, which is not
        // alphabetical or dictionary order. Schwung renders knobs first.
        let hierarchy: [String: Any] = [
            "osc1": ["label": "OSC 1", "knobs": ["detune", "shape"],
                     "params": [["key": "octave"], ["level": "root"]]],
            "root": ["label": "Main", "knobs": ["volume"],
                     "params": [["level": "filter"], ["level": "osc1"], ["level": "osc2"]]],
            "osc2": ["label": "OSC 2", "knobs": ["wave"]],
            "filter": ["label": "Filter", "knobs": ["cutoff"],
                       "params": ["resonance", ["key": "drive"]]]
        ]
        let pages = RemoteHierarchyLayout.levels(from: hierarchy)
        check(pages.map(\.id) == ["root", "filter", "osc1", "osc2"], "module navigation links determine page order")
        check(pages[0].name == "Main" && pages[1].name == "Filter", "hierarchy labels are preserved")
        check(pages[1].parameterKeys == ["cutoff", "resonance", "drive"], "knobs and list params retain order")
        check(pages[2].parameterKeys == ["detune", "shape", "octave"], "page knob order is preserved")
        let legacyPages = RemoteHierarchyLayout.levels(from: [
            "page10": ["name": "Ten", "params": ["b"]],
            "page2": ["name": "Two", "params": ["a"]]
        ])
        check(legacyPages.map(\.id) == ["page2", "page10"], "unlinked pages use natural numeric order")

        // Delayed device echoes should not pull a recently edited knob
        // backwards, but the device must eventually become authoritative.
        var reconcile = RemoteValueReconciler()
        reconcile.wrote("0.80", key: "slot:0:synth:cutoff", at: 10.0)
        check(!reconcile.accepts("0.20", key: "slot:0:synth:cutoff", at: 10.2), "recent stale echo must be ignored")
        check(reconcile.accepts("0.8", key: "slot:0:synth:cutoff", at: 10.3), "equivalent numeric echo confirms")
        check(reconcile.pending.isEmpty, "confirmation clears pending value")
        reconcile.wrote("0.80", key: "slot:0:synth:cutoff", at: 12.0)
        check(reconcile.accepts("0.70", key: "slot:0:synth:cutoff", at: 13.1), "later authoritative device update wins")
        check(reconcile.pending.isEmpty, "device reconciliation clears pending value")
        reconcile.wrote("1", key: "slot:0:slot:muted", at: 15.0)
        reconcile.wrote("0", key: "slot:1:slot:muted", at: 15.0)
        reconcile.clear(prefix: "slot:0:")
        check(reconcile.pending.count == 1, "component/slot cleanup must not clear other slots")
        reconcile.wrote("0.75", key: "slot:2:slot:volume", at: 15.0)
        reconcile.wrote("0.60", key: "slot:2:synth:cutoff", at: 15.0)
        reconcile.retainMixerWrites()
        check(reconcile.pending.count == 2, "page switches preserve mixer writes from all slots")
        check(reconcile.pending["slot:2:synth:cutoff"] == nil, "page switches discard stale editor writes")
        reconcile.clear()
        check(reconcile.pending.isEmpty, "disconnect drops optimistic pending state")

        // An interrupted or finished drag commits at most one final value.
        var gesture = RemoteGestureWrites()
        gesture.begin("synth:cutoff")
        check(gesture.end("synth:cutoff") == nil, "touch with no movement must not emit a final value")
        gesture.begin("synth:cutoff")
        gesture.changedValue("0.20", for: "synth:cutoff")
        gesture.changedValue("0.85", for: "synth:cutoff")
        check(gesture.end("synth:cutoff") == "0.85", "gesture completion must use last absolute value")
        check(gesture.end("synth:cutoff") == nil, "interrupted view cleanup must not duplicate final writes")
        gesture.begin("synth:drive")
        gesture.changedValue("0.6", for: "synth:drive")
        gesture.begin("fx1:mix")
        gesture.changedValue("0.4", for: "fx1:mix")
        gesture.clear(prefix: "synth:")
        check(gesture.end("synth:drive") == nil, "module swap drops abandoned gesture")
        check(gesture.end("fx1:mix") == "0.4", "module cleanup retains other component gestures")
        gesture.begin("synth:cutoff")
        gesture.changedValue("0.9", for: "synth:cutoff")
        gesture.clear()
        check(gesture.end("synth:cutoff") == nil, "disconnect clears gesture writes")

        // Removing a module invalidates its old unsent continuous control
        // values, without discarding a pending structural command or changes
        // to another module/slot.
        queue.clear()
        queue.enqueue("old synth cutoff", coalescingKey: "set_param:0:synth:cutoff")
        queue.enqueue("old synth resonance", coalescingKey: "set_param:0:synth:resonance")
        queue.enqueue("slot2 synth", coalescingKey: "set_param:1:synth:cutoff")
        queue.enqueue("fx1 mix", coalescingKey: "set_param:0:fx1:mix")
        queue.enqueue("structural", coalescingKey: nil)
        queue.enqueue("old synth drive", coalescingKey: "set_param:0:synth:drive")
        queue.discardContinuous(prefix: "set_param:0:synth:")
        check(queue.count == 3, "replacing synth only drops unsent synth controls for that slot")
        check(queue.dequeue()?.text == "slot2 synth", "preserves controls for another slot")
        check(queue.dequeue()?.text == "fx1 mix", "preserves another module")
        check(queue.dequeue()?.text == "structural", "preserves queued structural commands")
        queue.enqueue("master fx old", coalescingKey: "set_master_fx_param:-1:master_fx:fx2:mix")
        queue.enqueue("master fx other", coalescingKey: "set_master_fx_param:-1:master_fx:fx3:mix")
        queue.discardContinuous(prefix: "set_master_fx_param:-1:master_fx:fx2:")
        check(queue.count == 1 && queue.dequeue()?.text == "master fx other", "master FX positions are independently invalidated")

        // An unchanged device-confirmed value is never echoed back by the UI.
        // An unconfirmed value becomes eligible for ONE user-initiated
        // resend after the grace window, not an automatic background retry.
        var retry = RemoteValueReconciler()
        check(!retry.allowsUserWrite("0.5", key: "slot:0:synth:cutoff",
                                   lastReportedOrSent: "0.5", at: 20.0),
              "confirmed unchanged values must not be resent")
        retry.wrote("0.5", key: "slot:0:synth:cutoff", at: 20.0)
        check(!retry.allowsUserWrite("0.5", key: "slot:0:synth:cutoff",
                                   lastReportedOrSent: "0.5", at: 20.4),
              "too-recent unconfirmed write must not duplicate")
        check(retry.allowsUserWrite("0.5", key: "slot:0:synth:cutoff",
                                  lastReportedOrSent: "0.5", at: 21.1),
              "user may repeat an unconfirmed value after grace")
        check(retry.allowsUserWrite("0.7", key: "slot:0:synth:cutoff",
                                  lastReportedOrSent: "0.5", at: 20.1),
              "new user values always override an older pending write")
        retry.wrote("0.5", key: "slot:0:synth:cutoff", at: 21.1)
        check(!retry.allowsUserWrite("0.5", key: "slot:0:synth:cutoff",
                                   lastReportedOrSent: "0.5", at: 21.2),
              "a repeat attempt resets grace for its key")
        check(retry.accepts("0.50", key: "slot:0:synth:cutoff", at: 21.4),
              "numeric confirmation clears pending status")
        check(!retry.allowsUserWrite("0.5", key: "slot:0:synth:cutoff",
                                   lastReportedOrSent: "0.5", at: 30.0),
              "confirmed values never become retryable with age")

        // Metadata refreshes must retire obsolete local state selectively.
        let oldCutoff = RemoteParameter.parse([
            "key": "cutoff", "name": "Cutoff", "type": "float",
            "min": 0, "max": 1, "step": 0.01
        ], component: "synth")!
        let revisedCutoff = RemoteParameter.parse([
            "key": "cutoff", "name": "Cutoff", "type": "float",
            "min": 20, "max": 20000, "step": 1
        ], component: "synth")!
        let unchangedResonance = RemoteParameter.parse([
            "key": "resonance", "name": "Resonance", "type": "float",
            "min": 0, "max": 1, "step": 0.01
        ], component: "synth")!
        let retiredDrive = RemoteParameter.parse([
            "key": "drive", "name": "Drive", "type": "float",
            "min": 0, "max": 1, "step": 0.01
        ], component: "synth")!
        check(RemoteParameterMetadataDiff.invalidatedKeys(
            previous: [oldCutoff, unchangedResonance, retiredDrive],
            incoming: [revisedCutoff, unchangedResonance])
            == ["synth:cutoff", "synth:drive"],
            "changed and removed parameters invalidate stale writes and values")
        check(RemoteParameterMetadataDiff.invalidatedKeys(
            previous: [unchangedResonance],
            incoming: [unchangedResonance]).isEmpty,
            "identical metadata rebroadcast retains live gestures and values")
        check(RemoteParameterMetadataDiff.invalidatedKeys(
            previous: [], incoming: [revisedCutoff]).isEmpty,
            "new parameter discovery preserves early values")
        check(RemoteParameterMetadataDiff.invalidatedKeys(
            previous: [retiredDrive], incoming: []).count == 1,
            "empty new metadata retires previously known controls")
        var exactGesture = RemoteGestureWrites()
        exactGesture.begin("synth:cutoff")
        exactGesture.changedValue("0.5", for: "synth:cutoff")
        exactGesture.begin("synth:cutoff2")
        exactGesture.changedValue("0.9", for: "synth:cutoff2")
        exactGesture.clear(key: "synth:cutoff")
        check(exactGesture.end("synth:cutoff") == nil &&
              exactGesture.end("synth:cutoff2") == "0.9",
              "metadata cleanup does not erase similarly named knob gestures")
        var exactReconciler = RemoteValueReconciler()
        exactReconciler.wrote("0.1", key: "slot:0:synth:cutoff", at: 10)
        exactReconciler.wrote("0.7", key: "slot:0:synth:cutoff2", at: 10)
        exactReconciler.clear(key: "slot:0:synth:cutoff")
        check(exactReconciler.pending["slot:0:synth:cutoff"] == nil &&
              exactReconciler.pending["slot:0:synth:cutoff2"] != nil,
              "metadata cleanup preserves similarly named in-flight values")
        queue.clear()
        queue.enqueue("cutoff", coalescingKey: "set_param:0:synth:cutoff")
        queue.enqueue("cutoff2", coalescingKey: "set_param:0:synth:cutoff2")
        queue.enqueue("load", coalescingKey: nil)
        queue.discardContinuous(key: "set_param:0:synth:cutoff")
        check(queue.count == 2 && queue.dequeue()?.text == "cutoff2" &&
              queue.dequeue()?.text == "load",
              "exact queued-write cleanup preserves related parameters and load commands")

        // Two effects can reuse fx1:mix. A stale old parameter definition
        // must not be accepted just because its wire key still exists.
        let formerMix = RemoteParameter.parse([
            "key": "mix", "name": "Wet", "type": "float",
            "min": 0, "max": 1, "step": 0.01
        ], component: "fx1")!
        let replacementMix = RemoteParameter.parse([
            "key": "mix", "name": "Blend", "type": "float",
            "min": 0, "max": 100, "step": 1
        ], component: "fx1")!
        check(formerMix.wireKey == replacementMix.wireKey,
              "overlapping FX keys reproduce stale control risk")
        check(!RemoteParameterWritePolicy.isCurrent(formerMix, in: [replacementMix]),
              "old knob definition cannot write to a new effect with the same key")
        check(RemoteParameterWritePolicy.isCurrent(replacementMix, in: [replacementMix]),
              "current knob definition remains writable")
        check(!RemoteParameterWritePolicy.isCurrent(replacementMix, in: []),
              "removed module parameter cannot be written")
        let formerChoice = RemoteParameter.parse([
            "key": "mode", "name": "Mode", "type": "enum",
            "options": ["Off", "On"]
        ], component: "master_fx:fx1")!
        let newChoice = RemoteParameter.parse([
            "key": "mode", "name": "Mode", "type": "enum",
            "options": ["Low", "High"]
        ], component: "master_fx:fx1")!
        check(!RemoteParameterWritePolicy.isCurrent(formerChoice, in: [newChoice]),
              "old enum choices are rejected after Master FX metadata changes")

        // A delayed chain_params/param_update for an empty FX position must
        // not recreate controls after a valid device listing has removed it.
        let liveComponents = ["synth": "Drift", "fx1": "Delay"]
        check(RemoteChainMetadataPolicy.accepts(
              component: "fx2", confirmedSections: [],
              componentNames: liveComponents),
              "metadata can precede the first FX listing")
        check(RemoteChainMetadataPolicy.accepts(
              component: "fx2", confirmedSections: ["synth", "midi_fx"],
              componentNames: liveComponents),
              "partial slot listing must not suppress unknown FX metadata")
        check(!RemoteChainMetadataPolicy.accepts(
              component: "fx2", confirmedSections: ["fx"],
              componentNames: liveComponents),
              "confirmed empty FX cannot be resurrected by delayed metadata")
        check(RemoteChainMetadataPolicy.accepts(
              component: "fx1", confirmedSections: ["fx"],
              componentNames: liveComponents),
              "occupied FX still accepts its parameters")
        check(!RemoteChainMetadataPolicy.accepts(
              component: "midi_fx1", confirmedSections: ["midi_fx"],
              componentNames: liveComponents),
              "confirmed empty MIDI FX rejects orphan metadata")
        check(RemoteChainMetadataPolicy.accepts(
              component: "master_fx:fx1", confirmedSections: [],
              componentNames: [:]),
              "Master FX discovery can precede its first listing")
        check(!RemoteChainMetadataPolicy.accepts(
              component: "master_fx:fx1", confirmedSections: ["master_fx"],
              componentNames: [:]),
              "confirmed empty Master FX rejects late metadata")
        check(RemoteChainMetadataPolicy.section(for: "fx4") == "fx" &&
              RemoteChainMetadataPolicy.section(for: "midi_fx2") == "midi_fx" &&
              RemoteChainMetadataPolicy.section(for: "synth") == "synth",
              "component names resolve to their own section confidence")
        check(!RemoteChainMetadataPolicy.accepts(
              component: "unknown", confirmedSections: [],
              componentNames: [:]),
              "unrecognized components cannot masquerade as valid metadata")
        check(RemoteChainMetadataPolicy.moduleComponent(for: "fx2:mix") == "fx2",
              "slot FX parameters identify their component")
        check(RemoteChainMetadataPolicy.moduleComponent(for: "midi_fx1:rate") == "midi_fx1",
              "MIDI effect parameters identify their component")
        check(RemoteChainMetadataPolicy.moduleComponent(for: "master_fx:fx3:mix") == "master_fx:fx3",
              "Master FX parameter keys preserve their two-part prefix")
        check(RemoteChainMetadataPolicy.moduleComponent(for: "slot:volume") == nil,
              "slot mixer values are exempt from module metadata gating")
        check(RemoteChainMetadataPolicy.moduleComponent(for: "unknown:value") == nil,
              "unknown keys are not guessed into a module")

        // Repeated identical chain snapshots must preserve an active knob,
        // while direct hardware replacement/removal invalidates the old editor.
        let previousChain = ["master_fx:fx1": "Reverb A",
                             "master_fx:fx2": "Delay B"]
        check(RemoteChainChangePolicy.changedComponents(
              previous: previousChain, current: previousChain).isEmpty,
              "unchanged chain snapshots must preserve editor gestures")
        let changedChain = ["master_fx:fx1": "Reverb C",
                            "master_fx:fx3": "Filter D"]
        check(RemoteChainChangePolicy.changedComponents(
              previous: previousChain, current: changedChain)
              == ["master_fx:fx1", "master_fx:fx2", "master_fx:fx3"],
              "replacement, removal and addition invalidate only affected positions")
        check(RemoteChainChangePolicy.changedComponents(
              previous: ["synth": "Instrument A", "fx1": "Echo"],
              current: ["synth": "Instrument A", "fx1": "Delay"])
              == ["fx1"], "unrelated instrument editor remains stable")
        check(RemoteChainChangePolicy.changedComponents(
              previous: [:], current: [:]).isEmpty,
              "empty chain snapshots must not invalidate controls")

        // DSP path lookups for Master FX must be owned by the current action,
        // connection and editor. A clear/new swap invalidates the old token.
        func masterFXEligible(_ activeToken: Int?, socket: Int = 3,
                              editor: Int = 9, selected: Bool = true,
                              connected: Bool = true, cancelled: Bool = false) -> Bool {
            RemoteMasterFXLookupPolicy.isCurrent(
                expectedToken: 11, activeToken: activeToken,
                expectedSocketGeneration: 3, currentSocketGeneration: socket,
                expectedEditorGeneration: 9, currentEditorGeneration: editor,
                isConnected: connected, isMasterFXSelected: selected,
                cancelled: cancelled
            )
        }
        check(masterFXEligible(11), "current Master FX request may load")
        check(!masterFXEligible(12), "newer FX action invalidates older lookup")
        check(!masterFXEligible(nil), "cleared FX request token is invalid")
        check(!masterFXEligible(11, socket: 4), "reconnect invalidates FX lookup")
        check(!masterFXEligible(11, editor: 10), "navigation invalidates FX lookup")
        check(!masterFXEligible(11, selected: false), "leaving Master FX invalidates lookup")
        check(!masterFXEligible(11, connected: false), "disconnect invalidates lookup")
        check(!masterFXEligible(11, cancelled: true), "cancelled FX lookup cannot load")

        // Concurrent HTTP catalogue lookups must never publish stale results
        // or let an older completion stop the newer request's loading spinner.
        check(RemoteCatalogRequestPolicy.isCurrent(expectedGeneration: 4,
              currentGeneration: 4, cancelled: false),
              "latest catalogue request owns the response")
        check(!RemoteCatalogRequestPolicy.isCurrent(expectedGeneration: 4,
              currentGeneration: 5, cancelled: false),
              "superseded Move address response must be discarded")
        check(!RemoteCatalogRequestPolicy.isCurrent(expectedGeneration: 5,
              currentGeneration: 5, cancelled: true),
              "cancelled catalogue request must be discarded")

        // Malformed or duplicated saved workspace order should normalize
        // without hiding any of the three primary destinations.
        check(RemoteWorkspacePreferences.orderedViews("design,perform,chain") ==
              ["design", "perform", "chain"], "saved workspace order must be honored")
        check(RemoteWorkspacePreferences.orderedViews("design,design,obsolete") ==
              ["design", "perform", "chain"], "obsolete sections and duplicates must not persist")
        check(RemoteWorkspacePreferences.orderedViews("") ==
              ["perform", "chain", "design"], "fresh installs receive all three views")
        check(RemoteWorkspacePreferences.initialView("invalid") == "perform",
              "invalid launch workspace falls back to Perform")
        check(RemoteWorkspacePreferences.initialView("design") == "design",
              "user preferred starting workspace is preserved")
        check(RemoteWorkspacePreferences.movedOrder("perform,chain,design", from: 0, by: 1) ==
              ["chain", "perform", "design"], "workspace can be reordered")
        check(RemoteWorkspacePreferences.movedOrder("perform,chain,design", from: 0, by: -1) ==
              ["perform", "chain", "design"], "invalid order moves are ignored")

        // UI must not mistake a connected but incompletely reported chain
        // for an empty position. Add is permitted only for confirmed empties.
        check(RemoteChainPositionPresentation.resolve(
            connected: false, membershipConfirmed: true, moduleLoaded: false, bypassed: false) == .offline,
            "disconnected state must override old membership")
        check(RemoteChainPositionPresentation.resolve(
            connected: true, membershipConfirmed: false, moduleLoaded: false, bypassed: false) == .unknown,
            "unknown membership cannot be called empty")
        check(!RemoteChainPositionPresentation.resolve(
            connected: true, membershipConfirmed: false, moduleLoaded: false, bypassed: false).canAdd,
            "unknown membership must not offer Add")
        check(RemoteChainPositionPresentation.resolve(
            connected: true, membershipConfirmed: true, moduleLoaded: false, bypassed: false).canAdd,
            "confirmed empty position offers Add")
        check(RemoteChainPositionPresentation.resolve(
            connected: true, membershipConfirmed: true, moduleLoaded: true, bypassed: false) == .loaded,
            "loaded module has active state")
        check(RemoteChainPositionPresentation.resolve(
            connected: true, membershipConfirmed: true, moduleLoaded: true, bypassed: true) == .bypassed,
            "bypassed module must remain distinct from empty")
        let clearIntent = RemoteSlotClearIntent(destination: .slot1, component: "fx2")
        check(clearIntent.isCurrent(destination: .slot1), "Clear valid for original destination")
        check(!clearIntent.isCurrent(destination: .slot2), "Clear cannot retarget a new slot")
        check(clearIntent.component == "fx2", "Clear must retain original component")

        // A module-picker sheet captures the target selected when opened.
        // Switching slots or losing membership cannot silently retarget a swap.
        let capturedSlotPicker = RemoteModulePickerIntent(destination: .slot1, component: "fx2")
        check(capturedSlotPicker.id == "slot1:fx2",
              "module picker identity includes original slot and position")
        check(capturedSlotPicker.isCurrent(destination: .slot1, membershipConfirmed: true),
              "picker remains eligible on its original confirmed slot")
        check(!capturedSlotPicker.isCurrent(destination: .slot2, membershipConfirmed: true),
              "picker cannot replace a module in another slot")
        check(!capturedSlotPicker.isCurrent(destination: .slot1, membershipConfirmed: false),
              "picker cannot act after metadata is invalidated")
        let capturedMasterPicker = RemoteModulePickerIntent(
            destination: .masterFX, component: "master_fx:fx3"
        )
        check(capturedMasterPicker.component == "master_fx:fx3" &&
              !capturedMasterPicker.isCurrent(destination: .slot1, membershipConfirmed: true),
              "Master FX picker stays on its original master chain")

        // Hybrid workspace context restores only for the same instrument
        // and only when the instrument still exposes that group.
        check(RemoteWorkspaceContextPolicy.groupKey(
            destination: .slot1, moduleName: "Synth_esis") == "slot1:Synth_esis",
            "workspace context must include slot and module name")
        check(RemoteWorkspaceContextPolicy.groupKey(
            destination: .slot2, moduleName: "Synth_esis") == "slot2:Synth_esis",
            "workspace page selections cannot leak between slots")
        check(RemoteWorkspaceContextPolicy.groupKey(
            destination: .slot1, moduleName: "   ") == nil,
            "missing instrument identity cannot be used for restoration")
        let studioLevels = [
            RemoteLevel(id: "root", name: "Main", parameterKeys: []),
            RemoteLevel(id: "filter", name: "Filter", parameterKeys: [])
        ]
        check(RemoteWorkspaceContextPolicy.restoredGroup(
            "filter", available: studioLevels) == "filter",
            "previously selected group is restored when still advertised")
        check(RemoteWorkspaceContextPolicy.restoredGroup(
            "osc2", available: studioLevels) == nil,
            "disappeared module page must not be restored")
        check(RemoteWorkspaceContextPolicy.restoredGroup(
            "filter", available: []) == nil,
            "parameter group cannot restore before fresh metadata arrives")

        // Reconnection delays are capped and a stale or cancelled timer
        // cannot reopen a superseded socket generation.
        check(RemoteReconnectPolicy.delaySeconds(for: 0, maxRetries: 6) == nil,
              "attempt zero is invalid")
        check(RemoteReconnectPolicy.delaySeconds(for: 1, maxRetries: 6) == 1,
              "first retry backoff is one second")
        check(RemoteReconnectPolicy.delaySeconds(for: 2, maxRetries: 6) == 2,
              "second retry doubles the backoff")
        check(RemoteReconnectPolicy.delaySeconds(for: 6, maxRetries: 6) == 30,
              "retry delay is capped at thirty seconds")
        check(RemoteReconnectPolicy.delaySeconds(for: 7, maxRetries: 6) == nil,
              "retry limit is enforced")
        check(RemoteReconnectPolicy.retryIsCurrent(expectedGeneration: 5,
              currentGeneration: 5, wantsConnection: true, cancelled: false),
              "active retry may reconnect")
        check(!RemoteReconnectPolicy.retryIsCurrent(expectedGeneration: 5,
              currentGeneration: 6, wantsConnection: true, cancelled: false),
              "superseded socket generation cannot reconnect")
        check(!RemoteReconnectPolicy.retryIsCurrent(expectedGeneration: 5,
              currentGeneration: 5, wantsConnection: false, cancelled: false),
              "manual disconnect cancels retry eligibility")
        check(!RemoteReconnectPolicy.retryIsCurrent(expectedGeneration: 5,
              currentGeneration: 5, wantsConnection: true, cancelled: true),
              "cancelled retry cannot reopen socket")

        print("PASS: remote queue, module replacement, hierarchy, reconciliation, resend, metadata reconciliation, active control ownership, workspace preferences and context, stable module picker, chain certainty and clear intent, partial-chain metadata gating, chain invalidation, catalogue and Master FX ownership, reconnect policy")
    }
}
