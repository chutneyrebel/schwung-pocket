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

        print("PASS: remote queue, module replacement, hierarchy, reconciliation and user-driven resend")
    }
}
