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
struct RemoteSlotMixState {
    var muted: Bool?
    var soloed: Bool?
}

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
    @Published private(set) var componentNames: [String: String] = [:]
    @Published private(set) var midiFXCapacity = 1
    @Published private(set) var audioFXCapacity = 2
    @Published private(set) var masterFXCapacity = 4
    @Published private(set) var customToolUIURL: String?
    @Published private(set) var slotMixStates: [Int: RemoteSlotMixState] = [:]
    @Published private(set) var availableSlotModules: [RemoteSlotModule] = []
    @Published private(set) var isLoadingSlotModules = false
    @Published private(set) var slotModulesError: String?
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
    private var moduleCatalogTask: Task<Void, Never>?
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
        if case .masterFX = wireTarget { return componentNames[selectedMasterFXComponent] ?? selectedMasterFXComponent }
        if case .tool = wireTarget { return instrumentName.isEmpty ? "TOOL STATE" : instrumentName }
        return levels.first(where: { $0.id == selectedLevelID })?.name ?? instrumentName
    }

    @Published var selectedMasterFXComponent = "master_fx:fx1"

    /// Parameters for the selected hierarchy level, preserving Schwung's declared order.
    var visibleParameters: [RemoteParameter] {
        guard let level = levels.first(where: { $0.id == selectedLevelID }) else {
            return parameters.sorted(by: parameterDisplayOrder)
        }

        var ordered: [RemoteParameter] = []
        for key in level.parameterKeys {
            if let match = parameters.first(where: { $0.wireKey == key || $0.key == key }),
               !ordered.contains(match) {
                ordered.append(match)
            }
        }

        // Before a hierarchy arrives, retain the useful flat parameter view.
        if levels.isEmpty || (selectedLevelID == "root" && levels.count == 1 && ordered.isEmpty) {
            return parameters.sorted(by: parameterDisplayOrder)
        }
        return ordered
    }

    private func parameterDisplayOrder(_ lhs: RemoteParameter, _ rhs: RemoteParameter) -> Bool {
        let componentOrder = lhs.component.localizedCaseInsensitiveCompare(rhs.component)
        if componentOrder != .orderedSame { return componentOrder == .orderedAscending }
        let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.key < rhs.key
    }

    private func refreshOtherLevel() {
        guard !levels.isEmpty else { return }
        let baseLevels = levels.filter { $0.id != "other" }
        let referencedKeys = Set(baseLevels.flatMap(\.parameterKeys))
        let unassigned = parameters
            .filter { !referencedKeys.contains($0.key) && !referencedKeys.contains($0.wireKey) }
            .sorted(by: parameterDisplayOrder)
            .map(\.wireKey)

        levels = baseLevels
        if !unassigned.isEmpty {
            levels.append(RemoteLevel(id: "other", name: "Other", parameterKeys: unassigned))
        }
        levels.sort { left, right in
            if left.id == "root" { return right.id != "root" }
            if right.id == "root" { return false }
            if left.id == "other" { return false }
            if right.id == "other" { return true }
            let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.id < right.id
        }
        if !levels.contains(where: { $0.id == selectedLevelID }) {
            selectedLevelID = levels.first?.id ?? "root"
        }
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
            // Subscribe to the active destination first. The detailed UI should
            // not wait for the four mixer subscriptions before becoming live.
            let activeSlot: Int?
            switch wireTarget {
            case .slot(let slot):
                activeSlot = slot
                try await task.send(.string(Self.jsonString(["type": "subscribe", "slot": slot])))
                guard generation == connectionGeneration else { return }
                beginLoading()
            case .masterFX:
                activeSlot = nil
                try await task.send(.string(Self.jsonString(["type": "subscribe_master_fx"])))
                guard generation == connectionGeneration else { return }
                beginLoading()
            case .tool:
                activeSlot = nil
                try await task.send(.string(Self.jsonString(["type": "subscribe_tool"])))
                guard generation == connectionGeneration else { return }
                beginLoading()
            case .unverified:
                activeSlot = nil
            }

            guard generation == connectionGeneration else { return }
            connection = .connected
            retryAttempt = 0

            // Mixer tiles are secondary to the selected destination. Subscribe
            // after the receive loop starts so their setup cannot delay the UI.
            Task { [weak self] in
                for subscribedSlot in 0...3 where subscribedSlot != activeSlot {
                    guard !Task.isCancelled,
                          await self?.isCurrentGeneration(generation) == true else { return }
                    do {
                        try await task.send(.string(Self.jsonString(["type": "subscribe", "slot": subscribedSlot])))
                    } catch {
                        RemoteDiagnostics.log("background mixer subscription failed for slot \(subscribedSlot): \(error.localizedDescription)")
                        return
                    }
                }
            }

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

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == connectionGeneration && wantsConnection
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
            if isConnected { subscribe(slot: slot) } else { loadState = .idle }
        case .masterFX:
            if isConnected { beginLoading(); send(["type": "subscribe_master_fx"]) } else { loadState = .idle }
        case .tool:
            if isConnected { beginLoading(); send(["type": "subscribe_tool"]) } else { loadState = .idle }
        }
    }

    /// Re-requests the current destination's metadata.
    func refresh() {
        guard isConnected else { return }
        clearPresentedData()
        switch wireTarget {
        case .slot(let slot): subscribe(slot: slot)
        case .masterFX: beginLoading(); send(["type": "subscribe_master_fx"])
        case .tool: beginLoading(); send(["type": "subscribe_tool"])
        case .unverified: break
        }
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
        componentNames = [:]
        midiFXCapacity = 1
        audioFXCapacity = 2
        masterFXCapacity = 4
        customToolUIURL = nil
        parameters = []
        levels = []
        values = [:]
        selectedLevelID = "root"
        editingKeys.removeAll()
        lastSent.removeAll()
    }

    // MARK: Installed module discovery and hot-swap

    func loadSlotModules(address: String) {
        moduleCatalogTask?.cancel()
        isLoadingSlotModules = true
        slotModulesError = nil
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard !trimmed.isEmpty,
              var addressComponents = URLComponents(string: input),
              let originalScheme = addressComponents.scheme?.lowercased(),
              ["http", "https"].contains(originalScheme),
              let host = addressComponents.host, !host.isEmpty else {
            isLoadingSlotModules = false
            slotModulesError = trimmed.isEmpty
                ? "Move address is empty. Set it in Settings, then retry module discovery."
                : "Move address '\(trimmed)' could not be parsed. Use move.local:7700 or the Move IP with port 7700."
            RemoteDiagnostics.log("slot module discovery rejected address: '\(trimmed)'")
            return
        }
        addressComponents.path = ""
        addressComponents.query = nil
        addressComponents.fragment = nil
        guard let addressURL = addressComponents.url else {
            isLoadingSlotModules = false
            slotModulesError = "Could not build a URL from the Move address. Check the address and port in Settings."
            return
        }
        let schemes = originalScheme == "https" ? ["https", "http"] : [originalScheme]
        moduleCatalogTask = Task { [weak self] in
            defer { self?.isLoadingSlotModules = false }
            var lastError: Error?
            for scheme in schemes {
                guard var components = URLComponents(url: addressURL, resolvingAgainstBaseURL: false) else { continue }
                components.scheme = scheme
                components.host = host
                components.path = "/api/modules"
                components.query = nil
                components.fragment = nil
                guard let url = components.url else { continue }
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 8
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    let catalogue = try JSONDecoder().decode([RemoteSlotModule].self, from: data)
                    guard !Task.isCancelled else { return }
                    // Schwung 1.7.3 serves the full catalogue at /api/modules.
                    // Keep the picker focused on modules installed on the Move.
                    let modules = catalogue.filter { $0.installed == true }
                    self?.availableSlotModules = modules
                    self?.slotModulesError = modules.isEmpty ? "Schwung returned no installed modules. Install a module in Schwung Manager first." : nil
                    RemoteDiagnostics.log("slot module catalogue loaded from \(url.absoluteString): \(catalogue.count) catalogue entries, \(modules.count) installed")
                    return
                } catch {
                    lastError = error
                    RemoteDiagnostics.log("slot module catalogue failed at \(url.absoluteString): \(error.localizedDescription)")
                }
            }
            guard !Task.isCancelled else { return }
            self?.slotModulesError = "Could not load /api/modules over HTTPS or HTTP. Check the Move address and port 7700."
            if let lastError { RemoteDiagnostics.log("slot module catalogue exhausted fallbacks: \(lastError.localizedDescription)") }
        }
    }

    func swapModule(component: String, moduleID: String) {
        guard isConnected, case .slot(let slot) = wireTarget else { return }
        let expectedType: String
        if component == "synth" {
            expectedType = "sound_generator"
        } else if component.hasPrefix("midi_fx"), Int(component.dropFirst("midi_fx".count)) != nil {
            expectedType = "midi_fx"
        } else if component.hasPrefix("fx"), Int(component.dropFirst(2)) != nil {
            expectedType = "audio_fx"
        } else {
            slotModulesError = "This chain position cannot be changed from the app."
            return
        }
        guard let module = availableSlotModules.first(where: { $0.id == moduleID }),
              module.componentType == expectedType,
              !module.deviceOnly else {
            slotModulesError = "That module is unavailable for this chain position or must be loaded directly on the Move."
            return
        }
        parameters.removeAll { $0.component == component }
        values = values.filter { !$0.key.hasPrefix(component + ":") }
        lastSent = lastSent.filter { !$0.key.hasPrefix(component + ":") }
        beginLoading()
        send(["type": "set_param", "slot": slot, "key": "\(component):module", "value": module.id])
        RemoteDiagnostics.log("Requested module swap: slot=\(slot) component=\(component) module=\(module.id)")
    }

    func swapMasterFXModule(component: String, moduleID: String) {
        guard isConnected, case .masterFX = wireTarget else { return }
        guard component.range(of: #"^master_fx:fx[1-8]$"#, options: .regularExpression) != nil else {
            slotModulesError = "This Master FX position cannot be changed from the app."
            return
        }
        guard let module = availableSlotModules.first(where: { $0.id == moduleID }),
              module.componentType == "audio_fx",
              !module.deviceOnly,
              let dspPath = module.dsp_path,
              !dspPath.isEmpty else {
            slotModulesError = "That effect has no usable DSP path or cannot be loaded from the app."
            return
        }
        parameters.removeAll { $0.component == component }
        values = values.filter { !$0.key.hasPrefix(component + ":") }
        lastSent = lastSent.filter { !$0.key.hasPrefix(component + ":") }
        beginLoading()
        send(["type": "set_master_fx_param", "key": "\(component):module", "value": dspPath])
        RemoteDiagnostics.log("Requested Master FX swap: component=\(component) module=\(module.id)")
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

    func isSlotMuted(_ wireSlot: Int) -> Bool {
        slotMixStates[wireSlot]?.muted ?? false
    }

    func isSlotSoloed(_ wireSlot: Int) -> Bool {
        slotMixStates[wireSlot]?.soloed ?? false
    }

    private func updateSlotMixState(slot: Int, params: [String: Any]) {
        guard (0...3).contains(slot) else { return }
        var state = slotMixStates[slot] ?? RemoteSlotMixState()
        for (key, value) in params {
            let text: String?
            if let string = value as? String { text = string }
            else if let number = value as? NSNumber { text = number.stringValue }
            else { text = nil }
            guard let text else { continue }
            if key == "slot:muted" { state.muted = text == "1" || text.lowercased() == "true" }
            if key == "slot:soloed" { state.soloed = text == "1" || text.lowercased() == "true" }
        }
        slotMixStates[slot] = state
    }
    var slotReceiveChannel: String { values["slot:receive_channel"] ?? "0" }
    var slotForwardChannel: String { values["slot:forward_channel"] ?? "-1" }

    func refreshSlotMixStates() {
        guard isConnected else { return }
        for slot in 0...3 { subscribe(slot: slot) }
    }

    func setSlotVolume(_ proposed: Double) {
        let stepped = (min(max(proposed, 0), 4) / 0.05).rounded() * 0.05
        setSlotSetting("slot:volume", value: String(format: "%.2f", stepped))
    }

    func setSlotMuted(_ isMuted: Bool) {
        guard case .slot(let slot) = wireTarget else { return }
        setSlotMuted(isMuted, slot: slot)
    }

    func setSlotSoloed(_ isSoloed: Bool) {
        guard case .slot(let slot) = wireTarget else { return }
        setSlotSoloed(isSoloed, slot: slot)
    }

    func setSlotMuted(_ isMuted: Bool, slot: Int) {
        guard isConnected, (0...3).contains(slot) else { return }
        var state = slotMixStates[slot] ?? RemoteSlotMixState()
        state.muted = isMuted
        slotMixStates[slot] = state
        setSlotSetting("slot:muted", value: isMuted ? "1" : "0", slot: slot)
    }

    func setSlotSoloed(_ isSoloed: Bool, slot: Int) {
        guard isConnected, (0...3).contains(slot) else { return }
        var state = slotMixStates[slot] ?? RemoteSlotMixState()
        state.soloed = isSoloed
        slotMixStates[slot] = state
        setSlotSetting("slot:soloed", value: isSoloed ? "1" : "0", slot: slot)
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
        setSlotSetting(key, value: value, slot: slot)
    }

    private func setSlotSetting(_ key: String, value: String, slot: Int) {
        guard isConnected, (0...3).contains(slot) else { return }
        if case .slot(let selectedSlot) = wireTarget, selectedSlot == slot {
            values[key] = value
            lastSent[key] = value
        }
        send(["type": "set_param", "slot": slot, "key": key, "value": value])
    }

    private func sendParameter(_ text: String, for parameter: RemoteParameter) {
        values[parameter.wireKey] = text
        guard lastSent[parameter.wireKey] != text else { return }
        lastSent[parameter.wireKey] = text
        switch wireTarget {
        case .slot(let slot):
            send(["type": "set_param", "slot": slot, "key": parameter.wireKey, "value": text])
        case .masterFX:
            send(["type": "set_master_fx_param", "key": parameter.wireKey, "value": text])
        case .tool:
            // Tool state currently arrives without parameter type/range metadata.
            // Generic values stay read-only until Schwung exposes safe editable metadata.
            break
        case .unverified:
            break
        }
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
        // These two protocol messages are global and do not carry a slot.
        if type == "master_fx_info" {
            guard case .masterFX = wireTarget else { return }
            handleMasterFXInfo(message)
            return
        }
        if type == "tool_info" {
            guard case .tool = wireTarget else { return }
            handleToolInfo(message)
            return
        }
        if type == "custom_ui" {
            guard case .tool = wireTarget,
                  message["component"] as? String == "tool" else { return }
            let url = message["url"] as? String ?? ""
            customToolUIURL = url.isEmpty ? nil : url
            RemoteDiagnostics.log("Tool custom UI \(url.isEmpty ? "cleared" : "discovered")")
            return
        }
        if type == "param_update",
           let slot = message["slot"] as? Int,
           (0...3).contains(slot) {
            updateSlotMixState(slot: slot, params: message["params"] as? [String: Any] ?? [:])
        }
        if type == "error" {
            let messageText = message["message"] as? String ?? "Schwung Manager returned an error."
            RemoteDiagnostics.log("server error: \(messageText)")
            if loadState == .loading { loadState = .error(messageText) }
            return
        }

        switch wireTarget {
        case .slot(let currentSlot):
            guard let messageSlot = message["slot"] as? Int, messageSlot == currentSlot else {
                RemoteDiagnostics.log("ignored \(type) not addressed to current slot")
                return
            }
            switch type {
            case "slot_info": handleSlotInfo(message)
            case "hierarchy": handleHierarchy(message)
            case "chain_params": handleChainParams(message)
            case "param_update": handleParamUpdate(message)
            default: RemoteDiagnostics.log("unhandled message type \(type)")
            }
        case .masterFX:
            guard (message["slot"] as? Int) == 0 else { return }
            switch type {
            case "chain_params": handleMasterFXChainParams(message)
            case "param_update": handleParamUpdate(message)
            default: break
            }
        case .tool:
            guard (message["slot"] as? Int) == 0 else { return }
            if type == "param_update" { handleToolParamUpdate(message) }
        case .unverified:
            break
        }
    }

    private func handleMasterFXInfo(_ message: [String: Any]) {
        // Newer Schwung Manager builds explicitly mark an incomplete listing as
        // unknown. This is a transient state, not an empty Master FX chain and
        // not necessarily a malformed protocol response. Keep any last-known
        // names visible, but surface the uncertainty so they are not mistaken
        // for a confirmed live listing.
        if (message["unknown"] as? Bool) == true {
            RemoteDiagnostics.log("Master FX listing is temporarily unknown")
            loadState = .error("Master FX state is temporarily unknown. Tap Reload to try again.")
            loadTimeoutTask?.cancel()
            return
        }
        // Current Schwung sends a positional fx array and capacity. Older
        // Manager builds may only send fx1...fx4, so accept both wire shapes.
        let modules: [String]
        if let positional = message["fx"] as? [String] {
            modules = positional
        } else {
            let legacyKeys = ["fx1", "fx2", "fx3", "fx4"]
            guard legacyKeys.contains(where: { message[$0] is String }) else {
                loadState = .error("Schwung did not return a valid Master FX listing.")
                loadTimeoutTask?.cancel()
                return
            }
            modules = legacyKeys.map { message[$0] as? String ?? "" }
        }
        masterFXCapacity = min(max(message["cap"] as? Int ?? 4, 1), 8)
        var names: [String: String] = [:]
        for index in 0..<min(modules.count, masterFXCapacity) {
            let module = modules[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if !module.isEmpty { names["master_fx:fx\(index + 1)"] = module }
        }
        componentNames = names
        if !names.keys.contains(selectedMasterFXComponent) {
            selectedMasterFXComponent = names.keys.sorted().first ?? "master_fx:fx1"
        }
        if names.isEmpty {
            loadState = .loaded
            loadTimeoutTask?.cancel()
        }
    }

    private func handleToolInfo(_ message: [String: Any]) {
        let incomingID = (message["id"] as? String)
            ?? (message["name"] as? String)
            ?? (message["tool"] as? String)
            ?? ""
        let changed = incomingID != instrumentName
        instrumentName = incomingID
        if instrumentName.isEmpty {
            customToolUIURL = nil
            parameters = []
            values = [:]
            lastSent = [:]
        } else if changed {
            // Clear stale values only when a different Tool arrives. Repeated
            // tool_info announcements must not erase state already received.
            parameters = []
            values = [:]
            lastSent = [:]
        }

        // tool_info confirms that the Tool protocol responded. Its live state
        // arrives separately via param_update, and some Tools expose no flat
        // state values at all. Do not leave a responsive Tool stuck loading
        // until the generic response timeout expires.
        loadState = .loaded
        loadTimeoutTask?.cancel()
        RemoteDiagnostics.log("Tool info received: \(instrumentName.isEmpty ? "unnamed Tool" : instrumentName)")
    }

    private func handleMasterFXChainParams(_ message: [String: Any]) {
        guard let component = message["component"] as? String,
              component.range(of: #"^master_fx:fx[1-8]$"#, options: .regularExpression) != nil,
              let items = message["data"] as? [[String: Any]] else { return }
        let parsed = items.compactMap { RemoteParameter.parse($0, component: component) }
        parameters = parameters.filter { $0.component != component } + parsed
        loadState = .loaded
        loadTimeoutTask?.cancel()
    }

    private func handleToolParamUpdate(_ message: [String: Any]) {
        guard let params = message["params"] as? [String: Any] else { return }
        var merged = values
        for (key, value) in params where key.hasPrefix("overtake_dsp:") {
            let text: String?
            if let string = value as? String { text = string }
            else if let number = value as? NSNumber { text = number.stringValue }
            else { text = nil }
            guard let text else { continue }
            merged[key] = text
            if !parameters.contains(where: { $0.wireKey == key }) {
                let rawName = String(key.dropFirst("overtake_dsp:".count))
                parameters.append(RemoteParameter(
                    component: "tool", key: key,
                    name: rawName.replacingOccurrences(of: "_", with: " ").capitalized,
                    shortName: "", type: "tool_read_only", minimum: 0, maximum: 1,
                    step: 0.01, defaultValue: 0, options: [],
                    rawDefinition: "Tool value reported by overtake_dsp:state; parameter metadata is not exposed by the standard Tool protocol."
                ))
            }
        }
        values = merged
        for (key, value) in merged { lastSent[key] = value }
        loadState = .loaded
        loadTimeoutTask?.cancel()
    }

    private func handleSlotInfo(_ message: [String: Any]) {
        let unknownSections = Set(message["unknown"] as? [String] ?? [])
        let synthKnown = !unknownSections.contains("synth")
        let newName = message["synth"] as? String ?? ""
        RemoteDiagnostics.log("slot_info synth=\(synthKnown ? newName : "unknown")")

        if synthKnown, !instrumentName.isEmpty, newName != instrumentName, case .slot(let slot) = wireTarget {
            // Instrument was swapped on the device: old instrument metadata is no longer valid.
            let keepName = newName
            clearPresentedData()
            instrumentName = keepName
            subscribe(slot: slot)
            return
        }
        if synthKnown { instrumentName = newName }

        var names = componentNames
        if synthKnown {
            names.removeValue(forKey: "synth")
            if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                names["synth"] = newName
            }
        }

        // Newer Schwung versions provide positional lists and capacities. Older
        // versions provide only fx1/fx2/midi_fx1, so retain that wire fallback.
        if !unknownSections.contains("midi_fx") {
            if let modules = message["midi_fx"] as? [String] {
                names = names.filter { !$0.key.hasPrefix("midi_fx") }
                for (index, rawName) in modules.enumerated() {
                    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names["midi_fx\(index + 1)"] = name }
                }
                if let cap = message["midi_fx_cap"] as? Int {
                    midiFXCapacity = min(max(cap, 1), 8)
                } else {
                    midiFXCapacity = min(max(modules.count, 1), 8)
                }
            } else {
                if let rawName = message["midi_fx1"] as? String {
                    names.removeValue(forKey: "midi_fx1")
                    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names["midi_fx1"] = name }
                }
                midiFXCapacity = min(max(message["midi_fx_cap"] as? Int ?? 1, 1), 8)
            }
        } else if let cap = message["midi_fx_cap"] as? Int {
            midiFXCapacity = min(max(cap, 1), 8)
        }

        if !unknownSections.contains("fx") {
            if let modules = message["fx"] as? [String] {
                names = names.filter { key, _ in !(key.hasPrefix("fx") && Int(key.dropFirst(2)) != nil) }
                for (index, rawName) in modules.enumerated() {
                    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names["fx\(index + 1)"] = name }
                }
                if let cap = message["fx_cap"] as? Int {
                    audioFXCapacity = min(max(cap, 1), 8)
                } else {
                    audioFXCapacity = min(max(modules.count, 2), 8)
                }
            } else {
                for component in ["fx1", "fx2"] {
                    if let rawName = message[component] as? String {
                        names.removeValue(forKey: component)
                        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { names[component] = name }
                    }
                }
                audioFXCapacity = min(max(message["fx_cap"] as? Int ?? 2, 2), 8)
            }
        } else if let cap = message["fx_cap"] as? Int {
            audioFXCapacity = min(max(cap, 1), 8)
        }

        componentNames = names
        let allSectionsKnown = synthKnown && !unknownSections.contains("midi_fx") && !unknownSections.contains("fx")
        if allSectionsKnown && names.isEmpty {
            loadState = .loaded
            loadTimeoutTask?.cancel()
        }
    }

    private func handleHierarchy(_ message: [String: Any]) {
        guard let data = message["data"] as? [String: Any], let rawLevels = data["levels"] as? [String: Any] else {
            RemoteDiagnostics.log("hierarchy without levels")
            return
        }

        // The instrument dropdown must only consume the instrument's hierarchy.
        // Some Schwung builds label hierarchy messages with their chain component;
        // others omit that field, so also reject levels named after a known FX/MIDI-FX.
        if let component = message["component"] as? String, component != "synth" {
            RemoteDiagnostics.log("ignored hierarchy for non-instrument component \(component)")
            return
        }
        let nonInstrumentNames = Set(componentNames
            .filter { $0.key != "synth" }
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
        if rawLevels.values.contains(where: { value in
            guard let item = value as? [String: Any],
                  let name = item["name"] as? String else { return false }
            return nonInstrumentNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }) {
            RemoteDiagnostics.log("ignored hierarchy whose level name matches a non-instrument chain component")
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
        refreshOtherLevel()
        if !levels.contains(where: { $0.id == selectedLevelID }) { selectedLevelID = levels.first?.id ?? "root" }
    }

    private func handleChainParams(_ message: [String: Any]) {
        guard let component = message["component"] as? String,
              (component == "synth" ||
               component.range(of: #"^midi_fx[1-8]$"#, options: .regularExpression) != nil ||
               component.range(of: #"^fx[1-8]$"#, options: .regularExpression) != nil ||
               component.range(of: #"^master_fx:fx[1-8]$"#, options: .regularExpression) != nil) else {
            // Never silently classify an unlabelled FX response as instrument parameters.
            RemoteDiagnostics.log("chain_params missing or unknown component; ignored")
            return
        }
        guard let items = message["data"] as? [[String: Any]] else {
            RemoteDiagnostics.log("chain_params without array data")
            return
        }
        let parsed = items.compactMap { RemoteParameter.parse($0, component: component) }
        for parameter in parsed { RemoteDiagnostics.log(RemoteDiagnostics.describe(parameter)) }
        parameters = parameters.filter { $0.component != component } + parsed
        refreshOtherLevel()
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
