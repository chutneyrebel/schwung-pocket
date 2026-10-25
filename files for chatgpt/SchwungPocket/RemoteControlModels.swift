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
    /// No verified protocol exists in this codebase. No messages may be sent.
    case unverified(reason: String)
}

/// Single place that maps UI destinations to protocol addressing.
///
/// UNVERIFIED DETAILS (isolated here on purpose):
/// - Slots 1-4 use `slot == N`. This preserves v0.8.1 behaviour (the stepper label equalled the
///   wire value, and the observed traffic for the user's "slot 2" carried `"slot":2`). Whether the
///   Manager is 0-based internally has not been confirmed. Change `slotWireOffset` if testing shows
///   Slot 1 is wire slot 0.
/// - Master FX and Tool: the observed traffic only covers instrument slots. No evidence of how the
///   Remote UI addresses them exists in the project, so nothing is sent for them.
enum RemoteProtocolAdapter {
    static let slotWireOffset = -1

    static func target(for destination: RemoteDestination) -> RemoteWireTarget {
        switch destination {
        case .slot1: return .slot(1 + slotWireOffset)
        case .slot2: return .slot(2 + slotWireOffset)
        case .slot3: return .slot(3 + slotWireOffset)
        case .slot4: return .slot(4 + slotWireOffset)
        case .masterFX:
            return .unverified(reason: "Master FX control over the Remote UI hasn't been verified yet, so Schwung Pocket sends nothing for it. Capture the Manager's WebSocket traffic for Master FX to enable it.")
        case .tool:
            return .unverified(reason: "Tool control over the Remote UI hasn't been verified yet, so Schwung Pocket sends nothing for it. Capture the Manager's WebSocket traffic for a Tool to enable it.")
        }
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
            name: item["name"] as? String ?? key.replacingOccurrences(of: "_", with: " ").capitalized,
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
