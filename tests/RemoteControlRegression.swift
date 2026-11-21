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
        print("PASS: remote queue ordering, barriers, cleanup and parameter layout")
    }
}
