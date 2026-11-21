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

        print("PASS: remote queue, parameter layout, hierarchy ordering and cycle safety")
    }
}
