import Foundation
import Combine

/// Receives Note and CC events surfaced by the Move Mirror WebKit page.
@MainActor
final class MirrorMIDIActivityStore: ObservableObject {
    static let shared = MirrorMIDIActivityStore()

    @Published private(set) var events: [String] = []
    @Published private(set) var lastEventAt: Date?

    private init() {}

    func record(_ event: [String: Any]) {
        guard let label = event["label"] as? String,
              let action = event["action"] as? String else { return }
        let row = "\(label)  \(action)"
        if events.first != row { events.insert(row, at: 0) }
        events = Array(events.prefix(5))
        lastEventAt = Date()
    }
}
