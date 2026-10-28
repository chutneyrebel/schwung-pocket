import Foundation
import SwiftUI

/// Owns the Remote UI WebSocket, the selected destination, instrument metadata and parameter values.
/// Views only read published state and call the intent methods; no socket code lives in views.
///
/// Protocol messages used (confirmed in Schwung's Remote UI implementation):
///   out: subscribe / unsubscribe for slot, Master FX and Tool destinations
///   out: set_param for slot parameters; set_master_fx_param for Master FX parameters
///   in:  slot_info, hierarchy, chain_params, param_update, master_fx_info, tool_info
///
/// Slot subscriptions remain active for all four mixer tiles. The global Master FX and Tool
/// subscriptions are released when leaving those destinations. Incoming messages are filtered
/// against the active destination before they can change the displayed controls.
struct RemoteSlotMixState {
    var muted: Bool?
    var soloed: Bool?
    var volume: Double? = nil
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
    @Published private(set) var customComponentUIURLs: [String: String] = [:]
    @Published private(set) var slotMixStates: [Int: RemoteSlotMixState] = [:]
    @Published private(set) var slotVolumes: [Int: Double] = [:]
    @Published private(set) var slotInstrumentNames: [Int: String] = [:]
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
    private var toolRefreshTask: Task<Void, Never>?
    private var connectionGeneration = 0
    private var selectionGeneration = 0
    private var retryAttempt = 0
    private var wantsConnection = false
    private var resumeAfterBackground = false
    private var editingKeys = Set<String>()
    private var lastSent: [String: String] = [:]
    private var pendingMasterFXClears: [String: Date] = [:]
    private var mixerSubscriptionTask: Task<Void, Never>?
    private var mixerSubscriptionSentSlots = Set<Int>()
    private var loadedModuleCatalogAddress: String?

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
        if case .tool = wireTarget { startToolRefreshLoop() }
    }

    func disconnect() {
        wantsConnection = false
        resumeAfterBackground = false
        retryTask?.cancel()
        retryTask = nil
        toolRefreshTask?.cancel()
        toolRefreshTask = nil
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
        mixerSubscriptionTask?.cancel()
        mixerSubscriptionTask = nil
        mixerSubscriptionSentSlots.removeAll()
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
                mixerSubscriptionSentSlots.insert(slot)
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

            // Mixer tiles are secondary to the selected destination. Queue their
            // subscriptions gradually rather than placing three expensive full-slot
            // reads behind the active slot. A destination change cancels this queue.
            startBackgroundMixerSubscriptions(task: task, generation: generation, activeSlot: activeSlot)

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
        mixerSubscriptionTask?.cancel()
        mixerSubscriptionTask = nil

        // Schwung's Remote UI explicitly supports these unsubscribe messages.
        // Release the global Master FX / Tool subscriptions when leaving them;
        // slot subscriptions stay active because the mixer tiles need live state
        // for all four slots, including the non-selected ones.
        if case .tool = wireTarget {
            toolRefreshTask?.cancel()
            toolRefreshTask = nil
        }
        if isConnected {
            switch wireTarget {
            case .masterFX:
                send(["type": "unsubscribe_master_fx"])
            case .tool:
                send(["type": "unsubscribe_tool"])
            case .slot, .unverified:
                break
            }
        }

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
            startToolRefreshLoop()
        }
        if isConnected, let task = socket {
            startBackgroundMixerSubscriptions(
                task: task,
                generation: connectionGeneration,
                activeSlot: { if case .slot(let slot) = wireTarget { return slot }; return nil }()
            )
        }
    }

    /// Schwung's current server announces Tool arrival/removal, but does not
    /// announce an in-place swap while a Tool remains loaded. Re-subscribing
    /// only while the Tool destination is visible lets the server report the
    /// current ID without polling every other screen or adding protocol guesses.
    private func startToolRefreshLoop() {
        toolRefreshTask?.cancel()
        toolRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled, self.destination == .tool else { return }
                if self.isConnected {
                    self.send(["type": "subscribe_tool"])
                }
            }
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
        mixerSubscriptionSentSlots.insert(slot)
        send(["type": "subscribe", "slot": slot])
    }

    /// Subscribe to non-selected slots one at a time. Schwung handles a full slot
    /// subscription synchronously and can spend several seconds reading module
    /// parameters, so queueing all four at once delays later user selections.
    private func startBackgroundMixerSubscriptions(
        task: URLSessionWebSocketTask,
        generation: Int,
        activeSlot: Int?
    ) {
        mixerSubscriptionTask?.cancel()
        mixerSubscriptionTask = Task { [weak self] in
            for slot in 0...3 where slot != activeSlot {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled, let self,
                      self.isCurrentGeneration(generation) else { return }
                guard !self.mixerSubscriptionSentSlots.contains(slot) else { continue }
                do {
                    try await task.send(.string(Self.jsonString(["type": "subscribe", "slot": slot])))
                    guard !Task.isCancelled, self.isCurrentGeneration(generation) else { return }
                    self.mixerSubscriptionSentSlots.insert(slot)
                } catch {
                    RemoteDiagnostics.log("background mixer subscription failed for slot \(slot): \(error.localizedDescription)")
                    return
                }
            }
        }
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
        customComponentUIURLs = [:]
        parameters = []
        levels = []
        values = [:]
        selectedLevelID = "root"
        editingKeys.removeAll()
        lastSent.removeAll()
    }

    // MARK: Installed module discovery and hot-swap

    func loadSlotModules(address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // Returning to SchwungTroller should not re-fetch the same module catalogue
        // on every appearance. Those HTTP requests compete with live WebSocket control
        // traffic on the Move's local network. Failed/empty catalogues remain retryable.
        if loadedModuleCatalogAddress == trimmed, !availableSlotModules.isEmpty {
            RemoteDiagnostics.log("reusing cached slot module catalogue for \(trimmed)")
            return
        }
        moduleCatalogTask?.cancel()
        isLoadingSlotModules = true
        slotModulesError = nil
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
                    var catalogue = try JSONDecoder().decode([RemoteSlotModule].self, from: data)
                    guard !Task.isCancelled else { return }

                    // /api/modules is the broad catalogue used by the picker, but
                    // some versions omit dsp_path there. Master FX loads audio
                    // effects by absolute DSP path, supplied by /api/slot-modules.
                    // Enrich matching entries when that endpoint is available.
                    // The catalogue endpoint can work over HTTPS while the
                    // slot-module endpoint only responds over HTTP on some Move
                    // builds. Try both schemes independently; otherwise installed
                    // audio FX lose their required Master FX DSP path.
                    var slotModules: [RemoteSlotModule] = []
                    for slotScheme in schemes {
                        guard var slotComponents = URLComponents(url: addressURL, resolvingAgainstBaseURL: false) else { continue }
                        slotComponents.scheme = slotScheme
                        slotComponents.host = host
                        slotComponents.path = "/api/slot-modules"
                        slotComponents.query = nil
                        slotComponents.fragment = nil
                        guard let slotURL = slotComponents.url else { continue }
                        do {
                            var slotRequest = URLRequest(url: slotURL)
                            slotRequest.timeoutInterval = 5
                            let (slotData, slotResponse) = try await URLSession.shared.data(for: slotRequest)
                            guard let slotHTTP = slotResponse as? HTTPURLResponse,
                                  (200...299).contains(slotHTTP.statusCode) else { continue }
                            if let decoded = try? JSONDecoder().decode([RemoteSlotModule].self, from: slotData) {
                                slotModules = decoded
                                if !slotModules.isEmpty { break }
                            }
                        } catch {
                            RemoteDiagnostics.log("slot module DSP-path lookup failed on \(slotScheme): \(error.localizedDescription)")
                        }
                    }
                    if !slotModules.isEmpty {
                        let paths = Dictionary(slotModules.compactMap { module in
                            module.dsp_path.map { (module.id, $0) }
                        }, uniquingKeysWith: { first, _ in first })
                        catalogue = catalogue.map { module in
                            let installedMatch = slotModules.first(where: { $0.id == module.id })
                                ?? slotModules.first(where: {
                                    $0.name.caseInsensitiveCompare(module.name) == .orderedSame
                                        && $0.component_type == module.component_type
                                })
                            let path = module.dsp_path.flatMap { $0.isEmpty ? nil : $0 }
                                ?? paths[module.id]
                                ?? installedMatch?.dsp_path
                            guard let path, !path.isEmpty else { return module }
                            return RemoteSlotModule(
                                id: module.id,
                                name: module.name,
                                component_type: module.component_type,
                                device_only: module.device_only ?? installedMatch?.device_only ?? false,
                                dsp_path: path,
                                installed: module.installed ?? (installedMatch != nil),
                                installed_version: module.installed_version
                            )
                        }

                        // /api/slot-modules is the authoritative installed-on-disk list.
                        // Keep its entries even when /api/modules uses different IDs or
                        // omits a catalogue entry. In particular, Master FX needs the
                        // absolute dsp_path supplied by this endpoint.
                        for installedModule in slotModules where !catalogue.contains(where: {
                            $0.id == installedModule.id
                                || ($0.name.caseInsensitiveCompare(installedModule.name) == .orderedSame
                                    && $0.component_type == installedModule.component_type)
                        }) {
                            catalogue.append(RemoteSlotModule(
                                id: installedModule.id,
                                name: installedModule.name,
                                component_type: installedModule.component_type,
                                device_only: installedModule.device_only,
                                dsp_path: installedModule.dsp_path,
                                installed: true,
                                installed_version: installedModule.installed_version
                            ))
                        }
                    }
                    guard !Task.isCancelled else { return }
                    // Keep the picker focused on modules installed on the Move.
                    let modules = catalogue.filter { $0.installed == true }
                    self?.availableSlotModules = modules
                    self?.slotModulesError = modules.isEmpty ? "Schwung returned no installed modules. Install a module in Schwung Manager first." : nil
                    self?.loadedModuleCatalogAddress = modules.isEmpty ? nil : trimmed
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

    /// Removes the module from a slot chain position using Schwung's
    /// documented remote-UI convention: write "none" to "<component>:module".
    func clearSlotModule(component: String) {
        guard isConnected, case .slot(let slot) = wireTarget else { return }
        let isInstrument = component == "synth"
        let isMIDI = component.hasPrefix("midi_fx") && Int(component.dropFirst("midi_fx".count)) != nil
        let isAudio = component.hasPrefix("fx") && Int(component.dropFirst(2)) != nil
        guard isInstrument || isMIDI || isAudio else {
            slotModulesError = "This chain position cannot be cleared from the app."
            return
        }
        guard componentNames[component] != nil else { return }
        parameters.removeAll { $0.component == component }
        values = values.filter { !$0.key.hasPrefix(component + ":") }
        lastSent = lastSent.filter { !$0.key.hasPrefix(component + ":") }
        beginLoading()
        send(["type": "set_param", "slot": slot, "key": "\(component):module", "value": "none"])
        RemoteDiagnostics.log("Requested module clear: slot=\(slot) component=\(component)")
    }

    /// Schwung's chain host exposes per-module bypass flags independently of
    /// a module's own parameter metadata. This is distinct from slot mute.
    func hasComponentBypassState(_ component: String) -> Bool {
        values[component + ":bypassed"] != nil
    }

    func isComponentBypassed(_ component: String) -> Bool {
        let key = component + ":bypassed"
        return values[key] == "1" || values[key] == "true"
    }

    func setComponentBypassed(_ component: String, bypassed: Bool) {
        guard isConnected, componentNames[component] != nil else { return }
        let value = bypassed ? "1" : "0"
        switch wireTarget {
        case .slot(let slot):
            let isSupported = component == "synth"
                || component.range(of: #"^midi_fx[1-8]$"#, options: .regularExpression) != nil
                || component.range(of: #"^fx[1-8]$"#, options: .regularExpression) != nil
            guard isSupported else { return }
            values[component + ":bypassed"] = value
            send(["type": "set_param", "slot": slot, "key": component + ":bypassed", "value": value])
        case .masterFX:
            guard component.range(of: #"^master_fx:fx[1-8]$"#, options: .regularExpression) != nil else { return }
            values[component + ":bypassed"] = value
            send(["type": "set_master_fx_param", "key": component + ":bypassed", "value": value])
        case .tool, .unverified:
            // The standard Tool protocol has no generic bypass command.
            break
        }
        RemoteDiagnostics.log("Requested module bypass: destination=\(destination.title) component=\(component) bypassed=\(bypassed)")
    }

    /// Accept array responses and common object wrappers from different Schwung builds.
    /// Individual entries remain untyped so one incomplete module cannot invalidate the list.
    private static func moduleEntryDictionaries(from json: Any) -> [[String: Any]]? {
        if let array = json as? [Any] {
            let entries = array.compactMap { $0 as? [String: Any] }
            return entries.isEmpty ? nil : entries
        }
        guard let object = json as? [String: Any] else { return nil }
        for key in ["modules", "slot_modules", "slotModules", "items", "data", "results"] {
            if let nested = object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value,
               let entries = moduleEntryDictionaries(from: nested), !entries.isEmpty {
                return entries
            }
        }
        return nil
    }

    func swapMasterFXModule(component: String, moduleID: String) {
        guard isConnected, case .masterFX = wireTarget else { return }
        guard component.range(of: #"^master_fx:fx[1-8]$"#, options: .regularExpression) != nil else {
            slotModulesError = "This Master FX position cannot be changed from the app."
            return
        }
        guard let module = availableSlotModules.first(where: { $0.id == moduleID }),
              module.componentType == "audio_fx",
              !module.deviceOnly else {
            slotModulesError = "That effect is not available for Master FX or must be loaded directly on the Move."
            return
        }
        if let dspPath = module.dsp_path?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dspPath.isEmpty {
            sendMasterFXLoad(module: module, component: component, dspPath: dspPath)
            return
        }

        // The broad catalogue can omit dsp_path even though Schwung's installed
        // module endpoint has it. Resolve the selected effect directly at tap
        // time instead of making the user refresh the same incomplete catalogue.
        RemoteDiagnostics.log("Master FX swap missing cached DSP path; querying installed list for module=\(module.id)")
        Task { [weak self] in
            guard let self else { return }
            guard let addressURL = URL(string: self.address.contains("://") ? self.address : "https://\(self.address)"),
                  let host = addressURL.host else {
                self.slotModulesError = "Could not read the Move address. Check Settings and retry."
                return
            }
            let originalScheme = (addressURL.scheme ?? "https").lowercased()
            let schemes = originalScheme == "https" ? ["https", "http"] : [originalScheme]
            var lookupDiagnostics: [String] = []
            for scheme in schemes {
                guard var parts = URLComponents(url: addressURL, resolvingAgainstBaseURL: false) else {
                    lookupDiagnostics.append("\(scheme): invalid URL components")
                    continue
                }
                parts.scheme = scheme
                parts.host = host
                parts.path = "/api/slot-modules"
                parts.query = nil
                parts.fragment = nil
                guard let url = parts.url else {
                    lookupDiagnostics.append("\(scheme): invalid endpoint URL")
                    continue
                }
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        lookupDiagnostics.append("\(scheme): no HTTP response")
                        continue
                    }
                    guard (200...299).contains(http.statusCode) else {
                        lookupDiagnostics.append("\(scheme): HTTP \(http.statusCode)")
                        continue
                    }
                    // Parse the installed list loosely instead of decoding the whole
                    // response into RemoteSlotModule. A single older/custom entry
                    // with a missing field can make strict Codable decoding reject
                    // the entire array, hiding the DSP path for otherwise valid FX.
                    guard let json = try? JSONSerialization.jsonObject(with: data),
                          let installed = Self.moduleEntryDictionaries(from: json),
                          !installed.isEmpty else {
                        let preview = String(data: data.prefix(240), encoding: .utf8) ?? "<non-text response>"
                        lookupDiagnostics.append("\(scheme): could not find module entries in response (\(preview))")
                        continue
                    }
                    func field(_ entry: [String: Any], _ names: [String]) -> String? {
                        for name in names {
                            if let value = entry[name] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                return value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            if let pair = entry.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }),
                               let value = pair.value as? String,
                               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                return value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        return nil
                    }
                    let matches = installed.filter { entry in
                        let id = field(entry, ["id", "module_id", "moduleId"])
                        let name = field(entry, ["name", "display_name", "displayName"])
                        let type = field(entry, ["component_type", "componentType", "type"])
                        let identityMatches = id?.caseInsensitiveCompare(module.id) == .orderedSame
                            || name?.caseInsensitiveCompare(module.name) == .orderedSame
                        return identityMatches && (type == nil || type?.caseInsensitiveCompare("audio_fx") == .orderedSame)
                    }
                    if let match = matches.first,
                       let path = field(match, ["dsp_path", "dspPath", "dsp_path_abs", "dspPathAbs", "dsp", "path"]) {
                        guard self.isConnected, case .masterFX = self.wireTarget else { return }
                        RemoteDiagnostics.log("Master FX DSP path resolved using flexible installed-list parsing: module=\(module.id), path=\(path)")
                        self.sendMasterFXLoad(module: module, component: component, dspPath: path)
                        return
                    }
                    let matchingDetails = matches.map { entry in
                        let id = field(entry, ["id", "module_id", "moduleId"]) ?? "?"
                        let name = field(entry, ["name", "display_name", "displayName"]) ?? "?"
                        let type = field(entry, ["component_type", "componentType", "type"]) ?? "?"
                        let path = field(entry, ["dsp_path", "dspPath", "dsp_path_abs", "dspPathAbs", "dsp", "path"]) ?? "nil"
                        return "id=\(id), name=\(name), type=\(type), dsp_path=\(path)"
                    }
                    lookupDiagnostics.append("\(scheme): parsed \(installed.count) entries; matching entries: \(matchingDetails.isEmpty ? "none" : matchingDetails.joined(separator: "; "))")
                    RemoteDiagnostics.log("Master FX installed-list lookup diagnostics: \(lookupDiagnostics.last ?? "no detail")")
                } catch {
                    lookupDiagnostics.append("\(scheme): \(error.localizedDescription)")
                    RemoteDiagnostics.log("Master FX direct DSP lookup failed on \(scheme): \(error.localizedDescription)")
                }
            }
            // Compatibility fallback for older Manager builds that expose /api/modules
            // but predate /api/slot-modules. Schwung's own Master FX tests document this
            // exact installed DSP path for 4K EQ. Keep this narrowly scoped: guessing DSP
            // paths for arbitrary modules is unsafe because module.json may name another file
            // or the module may be installed in a different directory.
            if module.id == "4k-eq",
               lookupDiagnostics.contains(where: { $0.contains("HTTP 404") }) {
                let legacyDSPPath = "/data/UserData/schwung/modules/audio_fx/4k-eq/4k-eq.so"
                guard self.isConnected, case .masterFX = self.wireTarget else { return }
                RemoteDiagnostics.log("Using documented legacy Manager DSP path for 4K EQ: \(legacyDSPPath)")
                self.sendMasterFXLoad(module: module, component: component, dspPath: legacyDSPPath)
                return
            }

            let detail = lookupDiagnostics.joined(separator: " | ")
            self.slotModulesError = "Couldn't resolve \(module.name)'s DSP path. \(detail)"
            RemoteDiagnostics.log("Master FX swap failed: module=\(module.id); \(detail)")
        }
    }

    private func sendMasterFXLoad(module: RemoteSlotModule, component: String, dspPath: String) {
        slotModulesError = nil
        clearComponentPresentation(component)
        beginLoading()
        RemoteDiagnostics.log("Sending Master FX load: component=\(component) module=\(module.id) dsp_path=\(dspPath)")
        send(["type": "set_master_fx_param", "key": "\(component):module", "value": dspPath])
        refreshMasterFXAfterModuleAction()
    }

    /// The Master FX loader reports the final chain asynchronously. Request a
    /// fresh listing as a fallback so the UI also recovers if a notification is
    /// delayed or missed.
    private func refreshMasterFXAfterModuleAction() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, self.isConnected, case .masterFX = self.wireTarget else { return }
            self.send(["type": "subscribe_master_fx"])
        }
    }

    func clearMasterFXModule(component: String) {
        guard isConnected, case .masterFX = wireTarget else { return }
        guard component.range(of: #"^master_fx:fx[1-8]$"#, options: .regularExpression) != nil else {
            slotModulesError = "This Master FX position cannot be cleared from the app."
            return
        }
        // Allow the clear command even if the latest listing omitted the name.
        // The Move is authoritative about whether this position is occupied.
        slotModulesError = nil
        pendingMasterFXClears[component] = Date()
        clearComponentPresentation(component)
        beginLoading()
        // Schwung's Remote UI uses an empty DSP path to unload a Master FX
        // position. "none" is only the track-slot convention.
        send(["type": "set_master_fx_param", "key": "\(component):module", "value": ""])
        RemoteDiagnostics.log("Requested Master FX clear: component=\(component)")
        refreshMasterFXAfterModuleAction()
    }

    private func clearComponentPresentation(_ component: String) {
        // Remove the old module label as well as its controls immediately.
        // Otherwise the selected Master FX custom panel can remain visible
        // while Schwung processes the unload/swap request.
        componentNames.removeValue(forKey: component)
        parameters.removeAll { $0.component == component }
        values = values.filter { !$0.key.hasPrefix(component + ":") }
        lastSent = lastSent.filter { !$0.key.hasPrefix(component + ":") }
        customComponentUIURLs.removeValue(forKey: component)
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
            if key == "slot:volume", let raw = Double(text), raw.isFinite {
                let clamped = min(max(raw, 0), 4)
                state.volume = clamped
                slotVolumes[slot] = clamped
            }
        }
        slotMixStates[slot] = state
    }
    var slotReceiveChannel: String { values["slot:receive_channel"] ?? "0" }
    var slotForwardChannel: String { values["slot:forward_channel"] ?? "-1" }

    func refreshSlotMixStates() {
        guard isConnected else { return }
        for slot in 0...3 { subscribe(slot: slot) }
    }

    func slotVolume(for slot: Int) -> Double {
        min(max(slotVolumes[slot] ?? 1.0, 0), 4)
    }

    func setSlotVolume(_ proposed: Double) {
        guard case .slot(let slot) = wireTarget else { return }
        setSlotVolume(proposed, slot: slot)
    }

    func setSlotVolume(_ proposed: Double, slot: Int) {
        guard isConnected, (0...3).contains(slot) else { return }
        let stepped = (min(max(proposed, 0), 4) / 0.05).rounded() * 0.05
        slotVolumes[slot] = stepped
        setSlotSetting("slot:volume", value: String(format: "%.2f", stepped), slot: slot)
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
            let component = message["component"] as? String ?? ""
            let url = message["url"] as? String ?? ""
            switch wireTarget {
            case .tool where component == "tool":
                customToolUIURL = url.isEmpty ? nil : url
                RemoteDiagnostics.log("Tool custom UI \(url.isEmpty ? "cleared" : "discovered")")
            case .masterFX where component.range(of: #"^master_fx:fx[1-8]$"#, options: .regularExpression) != nil:
                if url.isEmpty {
                    customComponentUIURLs.removeValue(forKey: component)
                } else {
                    customComponentUIURLs[component] = url
                }
                RemoteDiagnostics.log("Master FX custom UI \(url.isEmpty ? "cleared" : "discovered") for \(component)")
            default:
                return
            }
            return
        }
        // Cache each slot's instrument label whenever Schwung reports slot_info,
        // even when that slot is not the currently selected destination.
        if type == "slot_info",
           let slot = message["slot"] as? Int,
           (0...3).contains(slot) {
            let unknown = Set(message["unknown"] as? [String] ?? [])
            if !unknown.contains("synth"), let name = message["synth"] as? String {
                let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
                slotInstrumentNames[slot] = cleaned.isEmpty ? nil : cleaned
            }
        }
        if type == "param_update",
           let slot = message["slot"] as? Int,
           (0...3).contains(slot) {
            updateSlotMixState(slot: slot, params: message["params"] as? [String: Any] ?? [:])
        }
        if type == "error" {
            let messageText = message["message"] as? String ?? "Schwung Manager returned an error."
            RemoteDiagnostics.log("server error: \(messageText)")
            if case .masterFX = wireTarget {
                // Keep server-side load/unload refusals visible instead of
                // allowing the subsequent listing refresh to hide the failure.
                slotModulesError = messageText
            }
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
            let component = "master_fx:fx\(index + 1)"
            let module = modules[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if let clearStarted = pendingMasterFXClears[component] {
                if Date().timeIntervalSince(clearStarted) < 2.5 {
                    // The command clears the device immediately, but an older
                    // master_fx_info can still be queued behind the clear. Do not
                    // resurrect that position from the stale listing.
                    continue
                }
                pendingMasterFXClears.removeValue(forKey: component)
            }
            if !module.isEmpty { names[component] = module }
        }
        // A Master FX position can be changed directly on the Move while this
        // screen remains open. Drop parameter metadata and cached values for any
        // position whose module changed or was removed; otherwise controls from
        // the previous effect can briefly remain visible or be written to it.
        let previousNames = componentNames
        let changedComponents = Set(previousNames.keys).union(names.keys).filter {
            previousNames[$0] != names[$0]
        }
        for component in changedComponents {
            parameters.removeAll { $0.component == component }
            values = values.filter { !$0.key.hasPrefix(component + ":") }
            lastSent = lastSent.filter { !$0.key.hasPrefix(component + ":") }
            customComponentUIURLs.removeValue(forKey: component)
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
            // A new Tool can arrive without leaving the Tool destination. Drop
            // the previous panel URL and state immediately; the matching
            // custom_ui and param_update messages will repopulate them.
            customToolUIURL = nil
            parameters = []
            values = [:]
            lastSent = [:]
            editingKeys.removeAll()
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
              let items = message["data"] as? [[String: Any]] else {
            RemoteDiagnostics.log("Master FX chain_params missing a valid component or parameter array")
            return
        }
        // A late chain_params response can arrive after an effect was removed
        // directly on the Move. Do not resurrect controls for an empty position.
        guard componentNames[component] != nil else {
            RemoteDiagnostics.log("ignored Master FX parameters for empty position \(component)")
            return
        }
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

        // slot_info is the authoritative chain listing. Remove stale controls
        // as soon as a component changes or disappears, rather than waiting for
        // a later page refresh or parameter response.
        let previousNames = componentNames
        let changedComponents = Set(previousNames.keys).union(names.keys).filter {
            previousNames[$0] != names[$0]
        }
        for component in changedComponents {
            clearComponentPresentation(component)
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
