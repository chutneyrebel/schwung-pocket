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

        print("PASS: remote queue, hierarchy and delayed-echo reconciliation")
    }
}
