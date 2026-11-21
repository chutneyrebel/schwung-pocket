import Foundation
import os

// MARK: - Destinations

/// The six destinations shown in the Native Controls selector.
/// Modelled explicitly: a destination is NOT assumed to be an integer slot.
enum RemoteDestination: String, CaseIterable, Identifiable, Hashable {
    case slot1, slot2, slot3, slot4, masterFX, tool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slot1: return "Slot 1"
        case .slot2: return "Slot 2"
        case .slot3: return "Slot 3"
        case .slot4: return "Slot 4"
        case .masterFX: return "Master FX"
        case .tool: return "Tool"
        }
    }

    var symbol: String {
        switch self {
        case .slot1, .slot2, .slot3, .slot4: return "pianokeys"
        case .masterFX: return "dial.medium"
        case .tool: return "wrench.and.screwdriver"
        }
    }
}

/// How a destination is addressed on the wire.
enum RemoteWireTarget: Equatable {
    /// Addressed through the `slot` field of the observed Remote UI messages.
    case slot(Int)
    case masterFX
    case tool
    /// No verified protocol exists in this codebase. No messages may be sent.
    case unverified(reason: String)
}

/// Single place that maps UI destinations to protocol addressing.
///
/// Verified against on-device tests: UI Slots 1-4 map to wire slot values 0-3.
/// Master FX and Tool use dedicated message types implemented by Schwung Manager.
enum RemoteProtocolAdapter {
    static let slotWireOffset = -1

    static func target(for destination: RemoteDestination) -> RemoteWireTarget {
        switch destination {
        case .slot1: return .slot(1 + slotWireOffset)
        case .slot2: return .slot(2 + slotWireOffset)
        case .slot3: return .slot(3 + slotWireOffset)
        case .slot4: return .slot(4 + slotWireOffset)
        case .masterFX: return .masterFX
        case .tool: return .tool
        }
    }
}

/// What Schwung can positively report about a Move slot's Schwung chain.
/// This does not identify Ableton stock devices when no Schwung module is present.
enum RemoteSlotModuleStatus: Equatable {
    case checking
    case schwung
    case none
    case unknown

    var label: String {
        switch self {
        case .checking: return "CHECKING"
        case .schwung: return "SCHWUNG MODULE"
        case .none: return "NO SCHWUNG MODULE"
        case .unknown: return "STATUS UNKNOWN"
        }
    }
}

struct RemoteSlotModule: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let component_type: String
    let device_only: Bool?
    let dsp_path: String?
    let installed: Bool?
    let installed_version: String?
    let subcategory: String?

    var componentType: String { component_type }
    var deviceOnly: Bool { device_only ?? false }

    /// Human-readable Schwung catalog subcategory for the hot-swap browser.
    var subcategoryTitle: String {
        let value = (subcategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels: [String: String] = [
            "polysynth": "Polysynth", "mono-bass": "Mono & Bass", "west-coast": "West Coast",
            "fm": "FM", "wavetable": "Wavetable", "sampler-rompler": "Sampler & Rompler",
            "drum-machine": "Drum Machine", "physical-modeling": "Physical Modeling",
            "chiptune-retro": "Chiptune & Retro", "granular": "Granular", "macro-hybrid": "Macro & Hybrid",
            "streaming-live-input": "Streaming & Live Input", "reverb": "Reverb", "delay-echo": "Delay & Echo",
            "modulation": "Modulation", "distortion-saturation": "Distortion & Saturation", "dynamics": "Dynamics",
            "filter-eq": "Filter & EQ", "granular-spectral": "Granular & Spectral",
            "looper-sampler-fx": "Looper & Sampler FX", "multi-fx": "Multi-FX", "utility": "Utility",
            "arpeggiator": "Arpeggiator", "sequencer": "Sequencer", "chord-harmony": "Chord & Harmony",
            "routing-utility": "Routing & Utility", "sampling-editing": "Sampling & Editing",
            "tuner-analysis": "Tuner & Analysis", "assistant": "Assistant", "performance": "Performance",
            "controller": "Controller", "sampler-looper": "Sampler & Looper", "performance-fx": "Performance FX"
        ]
        if let label = labels[value] { return label }
        guard !value.isEmpty else { return "Other / Uncategorised" }
        return value.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}

// MARK: - Parameters

enum RemoteControlKind: Equatable {
    /// Continuous numeric value shown as a rotary knob.
    case knob
    /// Discrete choice among `options`.
    case choice
    /// Shown but never edited (unknown or special protocol type).
    case readOnly(reason: String)
}

struct RemoteParameter: Identifiable, Hashable {
    let component: String
    let key: String
    let name: String
    let shortName: String
    let type: String
    let minimum: Double
    let maximum: Double
    let step: Double
    let defaultValue: Double
    let options: [String]
    /// Sorted-key JSON of the complete definition, kept for diagnostics.
    let rawDefinition: String

    var id: String { component + ":" + key }
    var wireKey: String { key.contains(":") ? key : component + ":" + key }
    var displayName: String { shortName.isEmpty ? name : shortName }

    /// Human-readable file-picker constraints reported by Schwung metadata.
    /// This is display-only; the app does not infer or write a path from it.
    var filepathDetails: String? {
        guard type == "filepath",
              let data = rawDefinition.data(using: .utf8),
              let definition = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var details: [String] = []
        if let root = definition["root"] as? String, !root.isEmpty {
            details.append("Folder: \(root)")
        }
        if let filter = definition["filter"] as? String, !filter.isEmpty {
            details.append("Files: \(filter)")
        } else if let filters = definition["filter"] as? [String], !filters.isEmpty {
            details.append("Files: \(filters.joined(separator: ", "))")
        }
        return details.isEmpty ? nil : details.joined(separator: "  ·  ")
    }

    var kind: RemoteControlKind {
        switch type {
        case "float":
            return .knob
        case "int":
            // Inferred: integer parameters use the same numeric string representation.
            return .knob
        case "enum":
            return options.isEmpty ? .readOnly(reason: "Choice parameter without options") : .choice
        case "init":
            return .readOnly(reason: "Initialization-type parameter. Its meaning on the device isn't confirmed, so it is shown read-only and nothing is sent for it.")
        case "canvas":
            // Canvas metadata points to a module-authored UI script, not a normal scalar control.
            // Keep it visible for context but never send guessed values from the native parameter editor.
            return options.isEmpty
                ? .readOnly(reason: "Custom Schwung status screen. This module draws its own interface (`status_view.js`); the native parameter panel cannot render that script yet. This is informational, not a connection error.")
                : .choice
        case "filepath":
            return .readOnly(reason: "Move-side file picker required. Schwung reports this as a file path, not a normal editable parameter. The native app does not yet expose the Move's file browser, so no file-path writes will be sent.")
        case "tool_read_only":
            return .readOnly(reason: "Schwung reports this Tool state value, but the standard Tool protocol does not provide editable control metadata. This value is read-only; no changes will be sent.")
        default:
            return .readOnly(reason: "Unsupported control type “\(type)”.")
        }
    }

    var isIntegral: Bool { type == "int" }

    /// Decimal places implied by the step, used for display and serialization.
    var decimals: Int {
        if isIntegral { return 0 }
        let text = String(step)
        guard let dot = text.firstIndex(of: "."), !text.contains("e") else { return 2 }
        let count = text.distance(from: dot, to: text.endIndex) - 1
        return min(max(count, 0), 4)
    }

    var safeStep: Double { step > 0 ? step : (isIntegral ? 1 : 0.01) }

    func clampedAndStepped(_ proposed: Double) -> Double {
        let low = minimum
        let high = max(maximum, minimum)
        let clamped = min(max(proposed, low), high)
        let stepped = low + ((clamped - low) / safeStep).rounded() * safeStep
        let bounded = min(max(stepped, low), high)
        let scale = pow(10.0, Double(max(decimals, 4)))
        return (bounded * scale).rounded() / scale
    }

    func format(_ value: Double) -> String {
        String(format: "%.\(decimals)f", value)
    }

    // MARK: Parsing

    static func parse(_ item: [String: Any], component: String) -> RemoteParameter? {
        guard let key = item["key"] as? String, !key.isEmpty else { return nil }
        let options: [String] = {
            if let strings = item["options"] as? [String] { return strings }
            if let any = item["options"] as? [Any] { return any.map { String(describing: $0) } }
            return []
        }()
        let type = (item["type"] as? String)?.lowercased() ?? "float"
        return RemoteParameter(
            component: component,
            key: key,
            name: item["name"] as? String ?? item["label"] as? String ?? key.replacingOccurrences(of: "_", with: " ").capitalized,
            shortName: item["short_name"] as? String ?? "",
            type: type,
            minimum: number(item["min"]) ?? 0,
            maximum: number(item["max"]) ?? 1,
            step: number(item["step"]) ?? 0.01,
            defaultValue: number(item["default"]) ?? 0,
            options: options,
            rawDefinition: compactJSON(item)
        )
    }

    static func number(_ any: Any?) -> Double? {
        let value: Double?
        if let n = any as? NSNumber { value = n.doubleValue }
        else if let s = any as? String { value = Double(s) }
        else { value = nil }
        guard let result = value, result.isFinite else { return nil }
        return result
    }

    static func compactJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: object) }
        return text.count > 800 ? String(text.prefix(800)) + "…" : text
    }
}

struct RemoteLevel: Identifiable, Hashable {
    let id: String
    let name: String
    let parameterKeys: [String]
}


// MARK: - Order-preserving parameter layout

/// Consecutive knobs share a grid. Choice and read-only controls retain their
/// original position instead of being moved to the end of the module page.
enum RemoteParameterLayout {
    static func groups(_ parameters: [RemoteParameter]) -> [[RemoteParameter]] {
        var result: [[RemoteParameter]] = []
        var knobs: [RemoteParameter] = []
        for parameter in parameters {
            if parameter.kind == .knob {
                knobs.append(parameter)
            } else {
                if !knobs.isEmpty {
                    result.append(knobs)
                    knobs.removeAll()
                }
                result.append([parameter])
            }
        }
        if !knobs.isEmpty { result.append(knobs) }
        return result
    }
}

// MARK: - Ordered WebSocket output queue

/// Keeps only the newest queued continuous value for a key within the current
/// command segment. Structural commands (nil key) are ordering barriers.
/// Does not discard module operations, toggles, or subscription commands.
struct RemoteOutboundQueue {
    struct Entry {
        let text: String
        let coalescingKey: String?
    }

    private(set) var entries: [Entry] = []
    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    mutating func enqueue(_ text: String, coalescingKey: String?) {
        if let key = coalescingKey {
            for index in entries.indices.reversed() {
                guard entries[index].coalescingKey != nil else { break }
                if entries[index].coalescingKey == key {
                    entries.remove(at: index)
                    break
                }
            }
        }
        entries.append(Entry(text: text, coalescingKey: coalescingKey))
    }

    /// Drop unsent continuous writes for an outgoing module instance before
    /// its replacement/clear command enters the queue. Preserve structural
    /// messages and writes for unrelated modules and mixer channels.
    mutating func discardContinuous(prefix: String) {
        entries.removeAll { entry in
            guard let key = entry.coalescingKey else { return false }
            return key.hasPrefix(prefix)
        }
    }

    mutating func dequeue() -> Entry? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }

    mutating func clear() { entries.removeAll() }
}


// MARK: - Schwung hierarchy page order

/// A hierarchy's `levels` field is a JSON object: its dictionary iteration
/// order is not the order the module presents pages. The root level declares
/// navigation links inside its ordered `params` array. Follow those links
/// first, then append unreachable levels in a stable numeric-key order.
enum RemoteHierarchyLayout {
    static func levels(from rawLevels: [String: Any]) -> [RemoteLevel] {
        let entries: [String: [String: Any]] = rawLevels.reduce(into: [:]) { result, pair in
            if let item = pair.value as? [String: Any] { result[pair.key] = item }
        }

        var visited = Set<String>()
        var orderedIDs: [String] = []

        func visit(_ id: String) {
            guard !visited.contains(id), let item = entries[id] else { return }
            visited.insert(id)
            orderedIDs.append(id)
            if let child = item["children"] as? String { visit(child) }
            for entry in item["params"] as? [Any] ?? [] {
                if let info = entry as? [String: Any],
                   let levelID = info["level"] as? String {
                    visit(levelID)
                }
            }
        }

        visit("root")
        let remainingIDs = entries.keys.sorted { left, right in
            let a = entries[left] ?? [:]
            let b = entries[right] ?? [:]
            let ai = (a["order"] as? Int) ?? (a["index"] as? Int) ?? (a["position"] as? Int)
            let bi = (b["order"] as? Int) ?? (b["index"] as? Int) ?? (b["position"] as? Int)
            if let ai, let bi, ai != bi { return ai < bi }
            if ai != nil && bi == nil { return true }
            if ai == nil && bi != nil { return false }
            return left.compare(right, options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
        for id in remainingIDs { visit(id) }

        return orderedIDs.compactMap { id in
            guard let item = entries[id] else { return nil }
            var keys: [String] = []
            var seen = Set<String>()
            func add(_ key: String) {
                if !key.isEmpty && seen.insert(key).inserted { keys.append(key) }
            }
            // Schwung renders its encoder `knobs` before the regular
            // `params` list. Each list has an explicit array order.
            for key in item["knobs"] as? [String] ?? [] { add(key) }
            for entry in item["params"] as? [Any] ?? [] {
                if let key = entry as? String { add(key) }
                else if let info = entry as? [String: Any],
                        let key = info["key"] as? String { add(key) }
            }
            return RemoteLevel(
                id: id,
                name: (item["label"] as? String) ?? (item["name"] as? String) ?? id.capitalized,
                parameterKeys: keys
            )
        }
    }
}




// MARK: - Active parameter write ownership

/// A view may finish a drag after its module has been replaced. The wire key
/// alone is insufficient: two unrelated FX can both publish "fx1:mix".
/// Require the entire parameter definition to match the current editor.
/// This is a local UI ownership check, not a claim that Schwung replies carry
/// module revisions.
enum RemoteParameterWritePolicy {
    static func isCurrent(_ parameter: RemoteParameter, in active: [RemoteParameter]) -> Bool {
        active.contains(parameter)
    }
}

// MARK: - Chain metadata gating

/// Parameter definitions can arrive after an effect was removed on Move.
/// Before the first complete listing, keep discovery compatible with builds
/// that send metadata first. Once a listing exists, its occupied component
/// names determine which component metadata is allowed back into the editor.
enum RemoteChainMetadataPolicy {
    static func accepts(component: String, knownListing: Bool,
                        componentNames: [String: String]) -> Bool {
        !knownListing || componentNames[component] != nil
    }

    /// Slot-level settings are not a module and remain valid independently.
    /// The Master FX keys have two component segments (master_fx:fxN).
    static func moduleComponent(for wireKey: String) -> String? {
        if wireKey.hasPrefix("master_fx:") {
            let parts = wireKey.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 3, parts[1].range(of: #"^fx[1-8]$"#, options: .regularExpression) != nil
            else { return nil }
            return "master_fx:" + String(parts[1])
        }
        let prefix = wireKey.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        if prefix == "synth" ||
           prefix.range(of: #"^(midi_fx|fx)[1-8]$"#, options: .regularExpression) != nil {
            return prefix
        }
        return nil
    }
}

// MARK: - Device-authoritative chain changes

/// A changed, added, or removed module invalidates its old parameter editor.
/// Unchanged component identities must not reset active knob gestures when
/// Schwung republishes an identical chain listing.
enum RemoteChainChangePolicy {
    static func changedComponents(previous: [String: String],
                                  current: [String: String]) -> [String] {
        Set(previous.keys).union(current.keys)
            .filter { previous[$0] != current[$0] }
            .sorted()
    }
}

// MARK: - Master FX asynchronous module resolution

/// An HTTP lookup may complete after the user clears/replaces the same FX,
/// navigates away, or reconnects. Only the request that still owns the exact
/// component and socket/editor generations can send a DSP-path load.
enum RemoteMasterFXLookupPolicy {
    static func isCurrent(expectedToken: Int, activeToken: Int?,
                          expectedSocketGeneration: Int, currentSocketGeneration: Int,
                          expectedEditorGeneration: Int, currentEditorGeneration: Int,
                          isConnected: Bool, isMasterFXSelected: Bool,
                          cancelled: Bool) -> Bool {
        activeToken == expectedToken
            && expectedSocketGeneration == currentSocketGeneration
            && expectedEditorGeneration == currentEditorGeneration
            && isConnected && isMasterFXSelected && !cancelled
    }
}

// MARK: - Async catalogue request ownership

/// Only the latest Move address lookup may publish module catalogue results.
/// Cancelling a task does not guarantee that a completed network callback
/// will be prevented from updating UI state.
enum RemoteCatalogRequestPolicy {
    static func isCurrent(expectedGeneration: Int, currentGeneration: Int,
                          cancelled: Bool) -> Bool {
        expectedGeneration == currentGeneration && !cancelled
    }
}

// MARK: - Connection retry policy

/// Pure reconnect backoff shared by production and deterministic CI tests.
/// Failed socket generations must not revive after a manual reconnect.
enum RemoteReconnectPolicy {
    static func delaySeconds(for attempt: Int, maxRetries: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= maxRetries else { return nil }
        return min(pow(2.0, Double(attempt - 1)), 30)
    }

    static func retryIsCurrent(expectedGeneration: Int, currentGeneration: Int,
                               wantsConnection: Bool, cancelled: Bool) -> Bool {
        expectedGeneration == currentGeneration && wantsConnection && !cancelled
    }
}

// MARK: - Final gesture write tracking

/// A control's final drag update may be lost while earlier absolute-value
/// writes are in flight. Send one final idempotent value at gesture completion.
/// A touch with no changed value never generates a write.
struct RemoteGestureWrites {
    private var editing = Set<String>()
    private var changed: [String: String] = [:]

    mutating func begin(_ key: String) {
        editing.insert(key)
        changed.removeValue(forKey: key)
    }

    mutating func changedValue(_ value: String, for key: String) {
        guard editing.contains(key) else { return }
        changed[key] = value
    }

    mutating func end(_ key: String) -> String? {
        guard editing.remove(key) != nil else { return nil }
        return changed.removeValue(forKey: key)
    }

    mutating func clear(prefix: String) {
        editing = Set(editing.filter { !$0.hasPrefix(prefix) })
        changed = changed.filter { !$0.key.hasPrefix(prefix) }
    }

    mutating func clear() {
        editing.removeAll()
        changed.removeAll()
    }
}

// MARK: - In-flight value reconciliation

/// A socket send is not a device acknowledgement. Keep an optimistic value
/// briefly while previously queued device echoes drain, then accept the Move's
/// authoritative value (including quantization or external automation).
/// All times are monotonic uptime supplied by the caller and injectable in tests.
struct RemoteValueReconciler {
    struct Pending {
        let value: String
        let createdAt: TimeInterval
    }

    private(set) var pending: [String: Pending] = [:]
    static let staleEchoGrace: TimeInterval = 1.0

    mutating func wrote(_ value: String, key: String, at uptime: TimeInterval) {
        pending[key] = Pending(value: value, createdAt: uptime)
    }

    /// The UI should not resend a device-confirmed value. However a value
    /// only written to the socket (not echoed by Schwung) may be explicitly
    /// sent again by a later user action once the echo grace has elapsed.
    /// This never schedules automatic retries.
    func allowsUserWrite(_ value: String, key: String,
                         lastReportedOrSent: String?, at uptime: TimeInterval) -> Bool {
        guard lastReportedOrSent == value else { return true }
        guard let unconfirmed = pending[key] else { return false }
        return uptime - unconfirmed.createdAt >= Self.staleEchoGrace
    }

    /// Returns whether the received device value should replace local state.
    mutating func accepts(_ deviceValue: String, key: String, at uptime: TimeInterval) -> Bool {
        guard let current = pending[key] else { return true }
        if Self.equivalent(current.value, deviceValue) {
            pending.removeValue(forKey: key)
            return true
        }
        if uptime - current.createdAt < Self.staleEchoGrace {
            return false
        }
        pending.removeValue(forKey: key)
        return true
    }

    mutating func clear(prefix: String) {
        pending = pending.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Navigating between parameter editors must not discard outstanding mixer
    /// writes from other slots. All other controls are page/module scoped.
    mutating func retainMixerWrites() {
        pending = pending.filter { key, _ in
            let parts = key.split(separator: ":")
            return parts.count == 4
                && parts[0] == "slot"
                && Int(parts[1]) != nil
                && parts[2] == "slot"
                && (parts[3] == "volume" || parts[3] == "muted" || parts[3] == "soloed")
        }
    }

    mutating func clear() { pending.removeAll() }

    private static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard let a = Double(lhs), let b = Double(rhs),
              a.isFinite, b.isFinite else { return false }
        return abs(a - b) < 0.00001
    }
}

// MARK: - Diagnostics

/// Development-only logging. Enable with the toggle on the Native Controls screen
/// (UserDefaults key below). Logs parameter metadata (keys/types/ranges) and message types only.
/// Never logs the Move address, and truncates values.
enum RemoteDiagnostics {
    static let defaultsKey = "SchwungPocket.RemoteDiagnostics.v1"
    private static let logger = Logger(subsystem: "app.schwungpocket", category: "remote-ui")

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }

    static func describe(_ parameter: RemoteParameter) -> String {
        "param key=\(parameter.wireKey) type=\(parameter.type) min=\(parameter.minimum) max=\(parameter.maximum) step=\(parameter.step) default=\(parameter.defaultValue) options=\(parameter.options.count) raw=\(parameter.rawDefinition)"
    }
}
