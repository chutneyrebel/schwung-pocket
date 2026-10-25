import Foundation
import SwiftUI

/// Owns the Remote UI WebSocket, the selected destination, instrument metadata and parameter values.
/// Views only read published state and call the intent methods; no socket code lives in views.
///
/// Protocol messages used (all observed by the user in the Manager, nothing invented):
///   out: {"type":"subscribe","slot":N}
///   out: {"type":"set_param","slot":N,"key":"synth:cutoff","value":"0.3"}
///   in:  slot_info, hierarchy, chain_params, param_update (each carries "slot")
///
/// NOT verified: an explicit unsubscribe message. None is sent. When the destination changes we
/// send a new `subscribe` and ignore any message whose `slot` is not the current destination.
@MainActor
final class RemoteControlStore: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(String)
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unsupported(String)
        case error(String)
    }

    @Published private(set) var connection: ConnectionState = .disconnected
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var destination: RemoteDestination = .slot1
    @Published private(set) var instrumentName = ""
    @Published private(set) var parameters: [RemoteParameter] = []
    @Published private(set) var levels: [RemoteLevel] = []
    @Published var selectedLevelID = "root"
    @Published private(set) var values: [String: String] = [:]

    private let maxRetries = 6
    private let loadTimeoutSeconds: UInt64 = 8

    private var address = ""
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var loadTimeoutTask: Task<Void, Never>?
    private var connectionGeneration = 0
    private var selectionGeneration = 0
    private var retryAttempt = 0
    private var wantsConnection = false
    private var resumeAfterBackground = false
    private var editingKeys = Set<String>()
    private var lastSent: [String: String] = [:]

    // MARK: Derived state

    var isConnected: Bool { connection == .connected }

    var wireTarget: RemoteWireTarget { RemoteProtocolAdapter.target(for: destination) }

    var statusText: String {
        switch connection {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .reconnecting(let attempt): return "Connection lost · reconnecting (\(attempt)/\(maxRetries))…"
        case .failed(let message): return message
        case .connected:
            switch loadState {
            case .idle: return "Connected"
            case .loading: return "Connected · loading \(destination.title)…"
            case .loaded: return "Connected · \(instrumentName.isEmpty ? destination.title : instrumentName)"
            case .unsupported: return "Connected · \(destination.title) not available yet"
            case .error(let message): return message
            }
        }
    }

    var currentLevelName: String {
        levels.first(where: { $0.id == selectedLevelID })?.name ?? instrumentName
    }

    /// Parameters for the selected level, in the order the device's hierarchy lists them.
    var visibleParameters: [RemoteParameter] {
        guard let level = levels.first(where: { $0.id == selectedLevelID }), !level.parameterKeys.isEmpty else { return parameters }
        var ordered: [RemoteParameter] = []
        for key in level.parameterKeys {
            if let match = parameters.first(where: { $0.wireKey == key || $0.key == key }), !ordered.contains(match) {
                ordered.append(match)
            }
        }
        return ordered
    }

    /// Full metadata dump for bug reports (no addresses, no values).
    var metadataReport: String {
        let header = "destination=\(destination.title) instrument=\(instrumentName)"
        return ([header] + parameters.map { RemoteDiagnostics.describe($0) }).joined(separator: "\n")
    }

    // MARK: Connection lifecycle

    func connect(address: String) {
        self.address = address
        wantsConnection = true
        resumeAfterBackground = false
        retryAttempt = 0
        retryTask?.cancel()
        openSocket(isRetry: false)
    }

    func disconnect() {
        wantsConnection = false
        resumeAfterBackground = false
        retryTask?.cancel()
        retryTask = nil
        loadTimeoutTask?.cancel()
        tearDownSocket()
        connection = .disconnected
        if loadState == .loading || loadState == .loaded { loadState = .idle }
        clearPresentedData()
    }

    func appDidEnterBackground() {
        guard wantsConnection else { return }
        let savedAddress = address
        disconnect()
        address = savedAddress
        resumeAfterBackground = true
    }

    func appDidBecomeActive() {
        guard resumeAfterBackground else { return }
        resumeAfterBackground = false
        connect(address: address)
    }

    private func openSocket(isRetry: Bool) {
        tearDownSocket()
        guard let url = Self.websocketURL(address: address) else {
            connection = .failed("Invalid Move address")
            wantsConnection = false
            return
        }
        let generation = connectionGeneration
        var request = URLRequest(url: url)
        let originScheme = url.scheme == "wss" ? "https" : "http"
        let originPort = url.port ?? (originScheme == "https" ? 443 : 80)
        request.setValue("\(originScheme)://\(url.host ?? "move.local"):\(originPort)", forHTTPHeaderField: "Origin")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        if !isRetry { connection = .connecting }
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.run(task: task, generation: generation)
        }
    }

    /// Invalidates the old socket (any in-flight callbacks see a stale generation and bail out).
    private func tearDownSocket() {
        connectionGeneration += 1
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func run(task: URLSessionWebSocketTask, generation: Int) async {
        do {
            if case .slot(let slot) = wireTarget {
                try await task.send(.string(Self.jsonString(["type": "subscribe", "slot": slot])))
                guard generation == connectionGeneration else { return }
                beginLoading()
            }
            guard generation == connectionGeneration else { return }
            connection = .connected
            retryAttempt = 0
            while !Task.isCancelled {
                let message = try await task.receive()
                guard generation == connectionGeneration else { return }
                switch message {
                case .string(let text): handle(text)
                case .data(let data): if let text = String(data: data, encoding: .utf8) { handle(text) }
                @unknown default: break
                }
            }
        } catch {
            guard generation == connectionGeneration, !Task.isCancelled else { return }
            handleConnectionLoss(error)
        }
    }

    private func handleConnectionLoss(_ error: Error) {
        RemoteDiagnostics.log("connection lost: \(error.localizedDescription)")
        tearDownSocket()
        guard wantsConnection else { return }
        retryAttempt += 1
        if retryAttempt > maxRetries {
            wantsConnection = false
            connection = .failed("Couldn't reach the Move. Check Wi-Fi and the address, then tap Connect.")
            if loadState == .loading { loadState = .error("Connection lost") }
            return
        }
        connection = .reconnecting(attempt: retryAttempt)
        let delaySeconds = min(pow(2.0, Double(retryAttempt - 1)), 30)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self, !Task.isCancelled, self.wantsConnection else { return }
            self.openSocket(isRetry: true)
        }
    }

    // MARK: Destination selection

    func select(_ newDestination: RemoteDestination) {
        guard newDestination != destination else { return }
        destination = newDestination
        clearPresentedData()
        switch wireTarget {
        case .unverified(let reason):
            loadState = .unsupported(reason)
        case .slot(let slot):
            if isConnected {
                subscribe(slot: slot)
            } else {
                loadState = .idle
            }
        }
    }

    /// Re-requests the current destination's metadata.
    func refresh() {
        guard isConnected, case .slot(let slot) = wireTarget else { return }
        clearPresentedData()
        subscribe(slot: slot)
    }

    private func subscribe(slot: Int) {
        beginLoading()
        send(["type": "subscribe", "slot": slot])
    }

    private func beginLoading() {
        loadState = .loading
        loadTimeoutTask?.cancel()
        let generation = selectionGeneration
        let seconds = loadTimeoutSeconds
        loadTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, !Task.isCancelled, generation == self.selectionGeneration, self.loadState == .loading else { return }
            self.loadState = .error("No response from the Move for \(self.destination.title).")
        }
    }

    /// Drops everything shown for the previous selection so stale values never look current.
    private func clearPresentedData() {
        selectionGeneration += 1
        loadTimeoutTask?.cancel()
        instrumentName = ""
        parameters = []
        levels = []
        values = [:]
        selectedLevelID = "root"
        editingKeys.removeAll()
        lastSent.removeAll()
    }

    // MARK: Parameter intents

    func beginEditing(_ parameter: RemoteParameter) { editingKeys.insert(parameter.wireKey) }
    func endEditing(_ parameter: RemoteParameter) { editingKeys.remove(parameter.wireKey) }

    func currentDouble(for parameter: RemoteParameter) -> Double {
        let raw = values[parameter.wireKey] ?? values[parameter.key]
        let parsed = raw.flatMap { Double($0) }.flatMap { $0.isFinite ? $0 : nil } ?? parameter.defaultValue
        return min(max(parsed, parameter.minimum), max(parameter.maximum, parameter.minimum))
    }

    func currentChoiceIndex(for parameter: RemoteParameter) -> Int {
        let lastIndex = max(parameter.options.count - 1, 0)
        func index(from number: Double) -> Int {
            // Clamp as a Double first: Int(_:) traps on out-of-range values.
            Int(min(max(number, 0), Double(lastIndex)))
        }
        guard let raw = values[parameter.wireKey] ?? values[parameter.key] else { return index(from: parameter.defaultValue) }
        if let number = Double(raw), number.isFinite { return index(from: number) }
        if let match = parameter.options.firstIndex(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) { return match }
        return index(from: parameter.defaultValue)
    }

    func displayValue(for parameter: RemoteParameter) -> String {
        switch parameter.kind {
        case .choice:
            let index = currentChoiceIndex(for: parameter)
            return parameter.options.indices.contains(index) ? parameter.options[index] : "—"
        case .knob:
            return parameter.format(currentDouble(for: parameter))
        case .readOnly:
            return values[parameter.wireKey] ?? values[parameter.key] ?? "—"
        }
    }

    func setNumeric(_ proposed: Double, for parameter: RemoteParameter) {
        guard parameter.kind == .knob else { return }
        let text = parameter.format(parameter.clampedAndStepped(proposed))
        sendParameter(text, for: parameter)
    }

    func setChoice(_ index: Int, for parameter: RemoteParameter) {
        guard parameter.kind == .choice else { return }
        let safe = min(max(index, 0), max(parameter.options.count - 1, 0))
        // Enums are sent as the option index, as in v0.8.1. Device-side acceptance is unverified for
        // every instrument; param_update replies may be an index or a label and both are understood.
        sendParameter(String(safe), for: parameter)
    }

    // MARK: Slot settings
    // These five keys and their wire encodings are defined by Schwung Manager's Remote UI.
    // They are independent of the loaded instrument's module parameter metadata.
    var slotVolume: Double {
        let raw = values["slot:volume"].flatMap { Double($0) } ?? 1.0
        return min(max(raw, 0), 4)
    }

    var slotMuted: Bool { values["slot:muted"] == "1" }
    var slotSoloed: Bool { values["slot:soloed"] == "1" }
    var slotReceiveChannel: String { values["slot:receive_channel"] ?? "0" }
    var slotForwardChannel: String { values["slot:forward_channel"] ?? "-1" }

    func setSlotVolume(_ proposed: Double) {
        let stepped = (min(max(proposed, 0), 4) / 0.05).rounded() * 0.05
        setSlotSetting("slot:volume", value: String(format: "%.2f", stepped))
    }

    func setSlotMuted(_ isMuted: Bool) {
        setSlotSetting("slot:muted", value: isMuted ? "1" : "0")
    }

    func setSlotSoloed(_ isSoloed: Bool) {
        setSlotSetting("slot:soloed", value: isSoloed ? "1" : "0")
    }

    func setSlotReceiveChannel(_ channel: String) {
        guard let value = Int(channel), (0...16).contains(value) else { return }
        setSlotSetting("slot:receive_channel", value: channel)
    }

    func setSlotForwardChannel(_ channel: String) {
        guard let value = Int(channel), (-2...15).contains(value) else { return }
        setSlotSetting("slot:forward_channel", value: channel)
    }

    private func setSlotSetting(_ key: String, value: String) {
        guard isConnected, case .slot(let slot) = wireTarget else { return }
        values[key] = value
        lastSent[key] = value
        send(["type": "set_param", "slot": slot, "key": key, "value": value])
    }

    private func sendParameter(_ text: String, for parameter: RemoteParameter) {
        guard case .slot(let slot) = wireTarget else { return }
        values[parameter.wireKey] = text
        guard lastSent[parameter.wireKey] != text else { return }
        lastSent[parameter.wireKey] = text
        send(["type": "set_param", "slot": slot, "key": parameter.wireKey, "value": text])
    }

    // MARK: Sending

    private func send(_ message: [String: Any]) {
        guard let task = socket else { return }
        let generation = connectionGeneration
        let text = Self.jsonString(message)
        Task { [weak self] in
            do { try await task.send(.string(text)) }
            catch {
                guard let self, generation == self.connectionGeneration else { return }
                self.handleConnectionLoss(error)
            }
        }
    }

    // MARK: Receiving

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = message["type"] as? String else {
            RemoteDiagnostics.log("ignored undecodable message")
            return
        }
        // Everything we act on is addressed to the current destination; anything else is late/stale.
        guard case .slot(let currentSlot) = wireTarget,
              let messageSlot = message["slot"] as? Int,
              messageSlot == currentSlot else {
            RemoteDiagnostics.log("ignored \(type) not addressed to current destination")
            return
        }

        switch type {
        case "slot_info": handleSlotInfo(message)
        case "hierarchy": handleHierarchy(message)
        case "chain_params": handleChainParams(message)
        case "param_update": handleParamUpdate(message)
        default: RemoteDiagnostics.log("unhandled message type \(type)")
        }
    }

    private func handleSlotInfo(_ message: [String: Any]) {
        let newName = message["synth"] as? String ?? ""
        let hasAnyComponent = ["synth", "fx1", "fx2", "midi_fx1"].contains { !((message[$0] as? String) ?? "").isEmpty }
        RemoteDiagnostics.log("slot_info synth=\(newName)")
        if !instrumentName.isEmpty, newName != instrumentName, case .slot(let slot) = wireTarget {
            // Instrument was swapped on the device: old metadata is no longer valid.
            let keepName = newName
            clearPresentedData()
            instrumentName = keepName
            subscribe(slot: slot)
            return
        }
        instrumentName = newName
        if !hasAnyComponent { loadState = .loaded; loadTimeoutTask?.cancel() }
    }

    private func handleHierarchy(_ message: [String: Any]) {
        guard let data = message["data"] as? [String: Any], let rawLevels = data["levels"] as? [String: Any] else {
            RemoteDiagnostics.log("hierarchy without levels")
            return
        }
        var found: [RemoteLevel] = []
        for (id, value) in rawLevels {
            guard let item = value as? [String: Any] else { continue }
            let name = item["name"] as? String ?? id.capitalized
            let keys: [String] = (item["params"] as? [Any] ?? []).compactMap { entry in
                if let string = entry as? String { return string }
                if let dict = entry as? [String: Any] { return dict["key"] as? String }
                return nil
            }
            found.append(RemoteLevel(id: id, name: name, parameterKeys: keys))
        }
        found.sort { left, right in
            if left.id == "root" { return right.id != "root" }
            if right.id == "root" { return false }
            let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.id < right.id
        }
        levels = found
        if !found.contains(where: { $0.id == selectedLevelID }) { selectedLevelID = found.first?.id ?? "root" }
    }

    private func handleChainParams(_ message: [String: Any]) {
        let component = message["component"] as? String ?? "synth"
        guard let items = message["data"] as? [[String: Any]] else {
            RemoteDiagnostics.log("chain_params without array data")
            return
        }
        let parsed = items.compactMap { RemoteParameter.parse($0, component: component) }
        for parameter in parsed { RemoteDiagnostics.log(RemoteDiagnostics.describe(parameter)) }
        parameters = parameters.filter { $0.component != component } + parsed
        loadState = .loaded
        loadTimeoutTask?.cancel()
    }

    private func handleParamUpdate(_ message: [String: Any]) {
        guard let params = message["params"] as? [String: Any] else { return }
        var merged = values
        for (key, value) in params {
            // Don't fight the user's finger: skip keys currently being dragged.
            if editingKeys.contains(key) { continue }
            if let string = value as? String { merged[key] = string }
            else if let number = value as? NSNumber { merged[key] = number.stringValue }
        }
        values = merged
        // Remember what the device reported so an unchanged knob never echoes it back.
        for (key, value) in merged where !editingKeys.contains(key) { lastSent[key] = value }
    }

    // MARK: Helpers

    static func websocketURL(address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let input = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: input), let host = components.host, !host.isEmpty else { return nil }
        let scheme = (components.scheme ?? "http").lowercased()
        components.scheme = (scheme == "https" || scheme == "wss") ? "wss" : "ws"
        components.path = "/ws/remote-ui"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func jsonString(_ message: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
