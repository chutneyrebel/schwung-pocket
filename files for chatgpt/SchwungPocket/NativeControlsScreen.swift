import SwiftUI
import UIKit
import WebKit

private struct SchwungChainComponent: Identifiable, Hashable {
    let rawValue: String
    let title: String
    let symbol: String

    var id: String { rawValue }

    static let instrument = SchwungChainComponent(
        rawValue: "synth", title: "Instrument", symbol: "waveform"
    )

    static func midiFX(_ position: Int) -> SchwungChainComponent {
        SchwungChainComponent(
            rawValue: "midi_fx\(position)",
            title: "MIDI FX \(position)",
            symbol: "pianokeys"
        )
    }

    static func audioFX(_ position: Int) -> SchwungChainComponent {
        SchwungChainComponent(
            rawValue: "fx\(position)",
            title: "Audio FX \(position)",
            symbol: "slider.horizontal.3"
        )
    }
}

/// SchwungTroller module: destination selector + metadata-driven parameter controls.
struct NativeControlsScreen: View {
    @ObservedObject var device: MoveConnectionStore
    @StateObject private var remote = RemoteControlStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RemoteDiagnostics.defaultsKey) private var diagnosticsEnabled = false
    @State private var copiedReport = false
    @State private var selectedChainComponent: SchwungChainComponent = .instrument
    @State private var showingModulePicker = false
    @State private var showingClearConfirmation = false

    var body: some View {
        ModuleScreenShell(
            eyebrow: "SCHWUNG POCKET / MODULE",
            title: "SchwungTroller",
            subtitle: "Live knobs and switches built from the instrument's own metadata."
        ) {
            connectionCard
            destinationCard
            if isInstrumentSlot {
                slotChainCard
            } else if isMasterFX {
                masterFXCard
            }
            contentSection
            if isInstrumentSlot {
                slotSettingsCard
            }
        }
        .onAppear {
            remote.loadSlotModules(address: device.addressText)
            // The WebSocket subscribes to all four mixer slots when it connects.
            // Keep those live subscriptions and cached M/S states when returning
            // from Mirror instead of sending four duplicate subscribe requests.
            if remote.connection == .disconnected { remote.connect(address: device.addressText) }
        }
        // Keep the remote subscription alive when switching between SchwungTroller and Mirror.
        // The scene-phase handler still manages background/foreground recovery.
        .onChange(of: scenePhase) { phase in
            if phase == .active { remote.appDidBecomeActive() }
            else if phase == .background { remote.appDidEnterBackground() }
        }
        .sheet(isPresented: $showingModulePicker) {
            if isMasterFX {
                ModuleSwapSheet(remote: remote, address: device.addressText, component: nil, masterFXComponent: remote.selectedMasterFXComponent)
            } else {
                ModuleSwapSheet(remote: remote, address: device.addressText, component: selectedChainComponent, masterFXComponent: nil)
            }
        }
        .alert("Clear \(selectedChainComponent.title)?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Module", role: .destructive) {
                remote.clearSlotModule(component: selectedChainComponent.rawValue)
            }
        } message: {
            Text("This unloads the module from the selected signal-chain position.")
        }
    }

    // MARK: Connection

    private var connectionCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(remote.statusText)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    switch remote.connection {
                    case .connected, .connecting, .reconnecting:
                        Button { remote.disconnect() } label: {
                            Label("Disconnect", systemImage: "xmark.circle.fill").font(.system(size: 13, weight: .bold))
                        }.buttonStyle(StudioSecondaryButton())
                    case .disconnected, .failed:
                        Button { remote.connect(address: device.addressText) } label: {
                            Label("Connect", systemImage: "dot.radiowaves.left.and.right").font(.system(size: 13, weight: .bold))
                        }.buttonStyle(StudioPrimaryButton())
                    }
                    if remote.isConnected {
                        Button { remote.refresh() } label: {
                            Label("Reload", systemImage: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                        }.buttonStyle(StudioSecondaryButton())
                    }
                }
                Toggle(isOn: $diagnosticsEnabled) {
                    Text("Developer diagnostics").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                }
                .tint(Theme.accent)
            }
        }
    }

    private var statusColor: Color {
        switch remote.connection {
        case .connected: return Theme.success
        case .connecting, .reconnecting: return Theme.warning
        case .disconnected: return Theme.muted
        case .failed: return Color.red
        }
    }

    // MARK: Destination selector

    private var destinationCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("REMOTE DESTINATION").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(remote.instrumentName.isEmpty ? " " : remote.instrumentName)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent).lineLimit(1)
                }
                DestinationSelector(
                    selection: remote.destination,
                    isConnected: remote.isConnected,
                    isMuted: remote.isSlotMuted,
                    isSoloed: remote.isSlotSoloed,
                    onMuteToggle: { slot, muted in remote.setSlotMuted(muted, slot: slot) },
                    onSoloToggle: { slot, soloed in remote.setSlotSoloed(soloed, slot: slot) }
                ) { destination in
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedChainComponent = .instrument
                        remote.select(destination)
                    }
                }
            }
        }
    }

    // MARK: Slot signal chain

    /// Positions come from slot_info capacities. Legacy Schwung builds default
    /// to the original one MIDI FX and two audio FX positions.
    private var chainComponents: [SchwungChainComponent] {
        (1...max(remote.midiFXCapacity, 1)).map { .midiFX($0) }
        + [.instrument]
        + (1...max(remote.audioFXCapacity, 1)).map { .audioFX($0) }
    }

    private var slotChainCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("SLOT SIGNAL CHAIN")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .center, spacing: 10) {
                    Text("MIDI FX → Instrument → Audio FX")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    Button {
                        remote.loadSlotModules(address: device.addressText)
                        showingModulePicker = true
                    } label: {
                        Label("Swap", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(StudioSecondaryButton())
                    .disabled(!remote.isConnected)
                    Button {
                        showingClearConfirmation = true
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(StudioSecondaryButton())
                    .disabled(!remote.isConnected || remote.componentNames[selectedChainComponent.rawValue] == nil)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(chainComponents) { component in
                        let selected = selectedChainComponent == component
                        let moduleName = remote.componentNames[component.rawValue]
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedChainComponent = component
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Image(systemName: component.symbol)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(component.title)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                Text(moduleName ?? "Not loaded")
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.muted)
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
                            }
                            .animation(.easeInOut(duration: 0.16), value: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(component.title), \(moduleName ?? "not loaded")")
                    }
                }
                Group {
                    if selectedChainComponent == .instrument && remote.levels.count > 1 {
                        Picker("Instrument parameter group", selection: $remote.selectedLevelID) {
                            ForEach(remote.levels) { level in Text(level.name).tag(level.id) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    } else if selectedChainComponent != .instrument {
                        Text("Controls for \(selectedChainComponent.title) appear below when Schwung reports editable parameters.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: 30, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    private var resolvedToolCustomUIURL: URL? {
        guard isTool, let raw = remote.customToolUIURL, !raw.isEmpty else { return nil }
        let address = device.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        let baseText = address.contains("://") ? address : "https://" + address
        guard let baseURL = URL(string: baseText),
              let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = baseComponents.scheme,
              let host = baseComponents.host else { return nil }
        guard let rawURL = URL(string: raw),
              var target = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) else { return nil }
        if target.scheme == nil {
            target = URLComponents(url: URL(string: raw, relativeTo: baseURL)?.absoluteURL ?? baseURL,
                                   resolvingAgainstBaseURL: false) ?? target
        }
        // Custom panels are served by the Move's Schwung Manager. Do not load
        // an arbitrary external host from a protocol message.
        guard target.host == nil || target.host?.caseInsensitiveCompare(host) == .orderedSame else { return nil }
        target.scheme = scheme
        target.host = host
        target.port = baseComponents.port
        var items = target.queryItems ?? []
        items.removeAll { ["schwungStandalone", "tool", "component"].contains($0.name) }
        items.append(URLQueryItem(name: "schwungStandalone", value: "1"))
        items.append(URLQueryItem(name: "tool", value: "1"))
        items.append(URLQueryItem(name: "component", value: "tool"))
        target.queryItems = items
        return target.url
    }

    private var selectedComponentParameters: [RemoteParameter] {
        if isMasterFX {
            return remote.parameters
                .filter { $0.component == remote.selectedMasterFXComponent }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        if isTool {
            return remote.parameters.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        if selectedChainComponent == .instrument {
            return remote.visibleParameters.filter { $0.component == selectedChainComponent.rawValue }
        }
        return remote.parameters
            .filter { $0.component == selectedChainComponent.rawValue }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var toolInfoCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(Theme.accent)
                    Text(remote.instrumentName.isEmpty ? "Tool subscription active" : remote.instrumentName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(remote.customToolUIURL == nil ? "STATE" : "WEB UI")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.accent)
                }
                Text(remote.customToolUIURL == nil
                     ? "Schwung has not advertised a custom web panel for this Tool. Reported state values, if available, appear below."
                     : (resolvedToolCustomUIURL == nil
                        ? "Schwung advertised a custom panel, but its URL could not be resolved safely for this Move address."
                        : "Schwung advertised a custom web panel. It should load below."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                if remote.customToolUIURL != nil && resolvedToolCustomUIURL == nil {
                    Text(remote.customToolUIURL ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                }
                if !remote.values.isEmpty {
                    ForEach(remote.values.keys.filter { $0.hasPrefix("overtake_dsp:") }.sorted(), id: \.self) { key in
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(key.dropFirst("overtake_dsp:".count)).replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.muted)
                            Spacer(minLength: 8)
                            Text(remote.values[key] ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Text("No flat Tool state values have arrived yet.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: Master FX

    private var masterFXCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("MASTER FX CHAIN")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .center, spacing: 10) {
                    Text("Select a loaded master-bus effect to inspect its live parameters.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    Button {
                        remote.loadSlotModules(address: device.addressText)
                        showingModulePicker = true
                    } label: {
                        Label("Swap", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(StudioSecondaryButton())
                    .disabled(!remote.isConnected)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(1...max(remote.masterFXCapacity, 1), id: \.self) { index in
                        let key = "master_fx:fx\(index)"
                        let moduleName = remote.componentNames[key]
                        let selected = remote.selectedMasterFXComponent == key
                        Button {
                            remote.selectedMasterFXComponent = key
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Master FX \(index)")
                                    .font(.system(size: 12, weight: .bold))
                                Text(moduleName ?? "Empty slot")
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.muted)
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Slot settings

    private var slotSettingsCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SLOT SETTINGS")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(remote.destination.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int((remote.slotVolume * 100).rounded()))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                    Slider(
                        value: Binding(
                            get: { remote.slotVolume },
                            set: { remote.setSlotVolume($0) }
                        ),
                        in: 0...4,
                        step: 0.05
                    )
                    .tint(Theme.accent)
                    .disabled(!remote.isConnected || !isInstrumentSlot)
                }

                Toggle(isOn: Binding(
                    get: { remote.slotMuted },
                    set: { remote.setSlotMuted($0) }
                )) {
                    Text("Muted").font(.system(size: 13, weight: .medium))
                }
                .tint(Theme.accent)
                .disabled(!remote.isConnected || !isInstrumentSlot)

                Toggle(isOn: Binding(
                    get: { remote.slotSoloed },
                    set: { remote.setSlotSoloed($0) }
                )) {
                    Text("Soloed").font(.system(size: 13, weight: .medium))
                }
                .tint(Theme.accent)
                .disabled(!remote.isConnected || !isInstrumentSlot)

                settingDivider

                VStack(alignment: .leading, spacing: 6) {
                    Text("Receive Channel").font(.system(size: 13, weight: .medium))
                    Picker("Receive Channel", selection: Binding(
                        get: { remote.slotReceiveChannel },
                        set: { remote.setSlotReceiveChannel($0) }
                    )) {
                        Text("All").tag("0")
                        ForEach(1...16, id: \.self) { channel in
                            Text("Channel \(channel)").tag(String(channel))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .disabled(!remote.isConnected || !isInstrumentSlot)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Forward Channel").font(.system(size: 13, weight: .medium))
                    Picker("Forward Channel", selection: Binding(
                        get: { remote.slotForwardChannel },
                        set: { remote.setSlotForwardChannel($0) }
                    )) {
                        Text("THRU").tag("-2")
                        Text("Auto").tag("-1")
                        ForEach(0...15, id: \.self) { channel in
                            Text("Channel \(channel + 1)").tag(String(channel))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .disabled(!remote.isConnected || !isInstrumentSlot)
                }

                if !isInstrumentSlot {
                    Text("These settings apply to Slots 1–4. Master FX and Tool use separate controls.")
                        .font(.system(size: 11)).lineSpacing(2).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var isInstrumentSlot: Bool {
        if case .slot = remote.wireTarget { return true }
        return false
    }

    private var isMasterFX: Bool {
        if case .masterFX = remote.wireTarget { return true }
        return false
    }

    private var isTool: Bool {
        if case .tool = remote.wireTarget { return true }
        return false
    }

    private var settingDivider: some View {
        Rectangle().fill(Theme.muted.opacity(0.2)).frame(height: 1)
    }

    // MARK: Content

    @ViewBuilder
    private var contentSection: some View {
        switch remote.loadState {
        case .unsupported(let reason):
            messageCard(icon: "lock.slash", title: "\(remote.destination.title) isn't available yet", text: reason)
        case .error(let message):
            PocketCard {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundStyle(Theme.warning)
                    Text(message).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Button {
                        if remote.isConnected { remote.refresh() } else { remote.connect(address: device.addressText) }
                    } label: { Label("Retry", systemImage: "arrow.clockwise").font(.system(size: 13, weight: .bold)) }
                        .buttonStyle(StudioPrimaryButton())
                }
            }
        case .loading:
            PocketCard {
                HStack(spacing: 12) {
                    ProgressView().tint(Theme.accent)
                    Text("Loading \(remote.destination.title)…").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
            }
        case .idle:
            messageCard(icon: "waveform.path.ecg", title: "Ready to discover controls",
                        text: remote.isConnected ? "Pick a destination above." : "Connect to Schwung to load the selected destination.")
        case .loaded:
            if isTool { toolInfoCard }
            if let customURL = resolvedToolCustomUIURL { toolCustomUICard(customURL) }
            if selectedComponentParameters.isEmpty {
                if isMasterFX {
                    let moduleName = remote.componentNames[remote.selectedMasterFXComponent]
                    let emptyText = moduleName == nil
                        ? "This Master FX position is empty. Load an effect on Move, then tap Reload."
                        : "Schwung reports \(moduleName ?? "this effect"), but returned no parameter metadata for it."
                    messageCard(icon: "square.dashed", title: "No Master FX controls", text: emptyText)
                } else if isTool {
                    let emptyText = remote.instrumentName.isEmpty
                        ? "No overtake Tool is currently loaded. Load a Tool in Schwung on Move, then tap Reload."
                        : (remote.customToolUIURL == nil
                            ? "Tool \(remote.instrumentName) has not reported flat state values and does not advertise a custom web UI."
                            : "Tool \(remote.instrumentName) has no native state values. Its custom web panel is shown above if the URL is supported.")
                    messageCard(icon: "wrench.and.screwdriver", title: "No native Tool controls", text: emptyText)
                } else {
                    let loadedName = remote.componentNames[selectedChainComponent.rawValue]
                    let emptyText = loadedName == nil
                        ? "No \(selectedChainComponent.title.lowercased()) is reported in this slot. Load one in Schwung on Move, then tap Reload."
                        : "Schwung reported \(loadedName ?? selectedChainComponent.title), but no editable parameters were returned."
                    messageCard(icon: "square.dashed", title: "\(selectedChainComponent.title) has no controls", text: emptyText)
                }
            } else {
                parameterBank(selectedComponentParameters)
            }
        }
    }

    private func toolCustomUICard(_ url: URL) -> some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .foregroundStyle(Theme.accent)
                    Text("TOOL CUSTOM PANEL")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.3)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Theme.success)
                }
                ToolCustomWebView(url: url)
                    .frame(minHeight: 260, idealHeight: 420, maxHeight: 620)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func messageCard(icon: String, title: String, text: String) -> some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 25)).foregroundStyle(Theme.violet)
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text(text).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.muted)
            }
        }
    }

    private func parameterBank(_ visible: [RemoteParameter]) -> some View {
        let knobs = visible.filter { $0.kind == .knob }
        let others = visible.filter { $0.kind != .knob }
        return PocketCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(remote.currentLevelName.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.accent)
                    Spacer()
                    Text("LIVE").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(Theme.success)
                }
                if !knobs.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6, alignment: .top)], alignment: .center, spacing: 14) {
                        ForEach(knobs) { parameter in knob(for: parameter) }
                    }
                }
                ForEach(others) { parameter in ParameterRow(parameter: parameter, remote: remote, diagnostics: diagnosticsEnabled) }
                if diagnosticsEnabled {
                    Button {
                        UIPasteboard.general.string = remote.metadataReport
                        copiedReport = true
                    } label: {
                        Label(copiedReport ? "Copied metadata" : "Copy parameter metadata", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                    }.buttonStyle(StudioSecondaryButton())
                }
            }
        }
    }

    private func knob(for parameter: RemoteParameter) -> some View {
        RotaryKnob(
            label: parameter.displayName,
            value: remote.currentDouble(for: parameter),
            range: parameter.minimum...max(parameter.maximum, parameter.minimum),
            step: parameter.safeStep,
            valueText: remote.displayValue(for: parameter),
            onEditingChanged: { editing in
                if editing { remote.beginEditing(parameter) } else { remote.endEditing(parameter) }
            },
            onChange: { remote.setNumeric($0, for: parameter) }
        )
    }
}

// MARK: - Destination selector

/// Six tappable boxes in a 3x2 grid. Fits narrow iPhones without horizontal scrolling or clipping.
struct DestinationSelector: View {
    let selection: RemoteDestination
    let isConnected: Bool
    let isMuted: (Int) -> Bool
    let isSoloed: (Int) -> Bool
    let onMuteToggle: (Int, Bool) -> Void
    let onSoloToggle: (Int, Bool) -> Void
    let onSelect: (RemoteDestination) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private func wireSlot(for destination: RemoteDestination) -> Int? {
        switch destination {
        case .slot1: return 0
        case .slot2: return 1
        case .slot3: return 2
        case .slot4: return 3
        case .masterFX, .tool: return nil
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(RemoteDestination.allCases) { destination in
                let isSelected = destination == selection
                let slot = wireSlot(for: destination)
                VStack(spacing: 6) {
                    Button { onSelect(destination) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: destination.symbol).font(.system(size: 15, weight: .semibold))
                            Text(destination.title)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(destination.title)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

                    if let slot {
                        HStack(spacing: 6) {
                            Button {
                                onMuteToggle(slot, !isMuted(slot))
                            } label: {
                                Text("M")
                                    .font(.system(size: 11, weight: .heavy))
                                    .frame(maxWidth: .infinity, minHeight: 23)
                                    .foregroundStyle(isMuted(slot) ? Color.white : Theme.muted)
                                    .background(isMuted(slot) ? Theme.warning : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Slot \(slot + 1) mute")
                            .disabled(false)

                            Button {
                                onSoloToggle(slot, !isSoloed(slot))
                            } label: {
                                Text("S")
                                    .font(.system(size: 11, weight: .heavy))
                                    .frame(maxWidth: .infinity, minHeight: 23)
                                    .foregroundStyle(isSoloed(slot) ? Theme.background : Theme.muted)
                                    .background(isSoloed(slot) ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Slot \(slot + 1) solo")
                        }
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity, minHeight: slot == nil ? 66 : 78)
                .background(isSelected ? Theme.accent.opacity(0.13) : Theme.surfaceRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.06), lineWidth: 1)
                }
            }
        }
    }
}

private struct ModuleSwapSheet: View {
    @ObservedObject var remote: RemoteControlStore
    let address: String
    let component: SchwungChainComponent?
    let masterFXComponent: String?
    @Environment(\.dismiss) private var dismiss
    @State private var pendingModule: RemoteSlotModule?

    private var displayTitle: String {
        component?.title ?? masterFXComponent?.replacingOccurrences(of: "master_fx:", with: "").uppercased() ?? "Master FX"
    }

    private var expectedType: String {
        guard let component else { return "audio_fx" }
        if component.rawValue == "synth" { return "sound_generator" }
        if component.rawValue.hasPrefix("midi_fx") { return "midi_fx" }
        return "audio_fx"
    }

    private var choices: [RemoteSlotModule] {
        remote.availableSlotModules
            .filter { $0.componentType == expectedType && !$0.deviceOnly }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Choose an installed module for \(displayTitle). The selected position will be replaced on the Move.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if remote.isLoadingSlotModules {
                    HStack { ProgressView(); Text("Reading installed modules…") }
                }
                if let error = remote.slotModulesError {
                    Section {
                        Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Retry module discovery") { remote.loadSlotModules(address: address) }
                    }
                }
                Section("Installed \(displayTitle) modules") {
                    if choices.isEmpty {
                        Text("No compatible modules found. Check that Schwung supports /api/slot-modules and try again.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(choices) { module in
                        Button {
                            pendingModule = module
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(module.name).foregroundStyle(.primary)
                                Text(module.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Swap \(displayTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { remote.loadSlotModules(address: address) }
                        .disabled(remote.isLoadingSlotModules)
                }
            }
            .confirmationDialog(
                "Replace \(displayTitle)?",
                isPresented: Binding(
                    get: { pendingModule != nil },
                    set: { if !$0 { pendingModule = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let module = pendingModule {
                    Button("Replace with \(module.name)", role: .destructive) {
                        if let component {
                            remote.swapModule(component: component.rawValue, moduleID: module.id)
                        } else if let masterFXComponent {
                            remote.swapMasterFXModule(component: masterFXComponent, moduleID: module.id)
                        }
                        pendingModule = nil
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { pendingModule = nil }
            } message: {
                Text("This replaces the module currently loaded in this chain position.")
            }
        }
        .onAppear { remote.loadSlotModules(address: address) }
    }
}

// MARK: - Non-knob parameter rows

/// Renders choices and read-only/unknown parameters. Unknown types never crash and never send data.
private struct ParameterRow: View {
    let parameter: RemoteParameter
    @ObservedObject var remote: RemoteControlStore
    let diagnostics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(parameter.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(remote.displayValue(for: parameter))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.accent)
            }
            switch parameter.kind {
            case .choice:
                choicePicker
            case .readOnly(let reason):
                Text(reason).font(.system(size: 10)).foregroundStyle(Theme.muted)
                DisclosureGroup("Raw definition") {
                    Text(parameter.rawDefinition)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11)).tint(Theme.accent).foregroundStyle(Theme.muted)
            case .knob:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var choicePicker: some View {
        let binding = Binding<Int>(
            get: { remote.currentChoiceIndex(for: parameter) },
            set: { remote.setChoice($0, for: parameter) }
        )
        if parameter.options.count <= 3 {
            Picker(parameter.name, selection: binding) {
                ForEach(Array(parameter.options.enumerated()), id: \.offset) { item in Text(item.element).tag(item.offset) }
            }
            .pickerStyle(.segmented).tint(Theme.accent)
        } else {
            Picker(parameter.name, selection: binding) {
                ForEach(Array(parameter.options.enumerated()), id: \.offset) { item in Text(item.element).tag(item.offset) }
            }
            .pickerStyle(.menu).tint(Theme.accent)
        }
    }
}

/// Hosts a module's own Schwung Remote UI. In standalone mode the module's
/// bundled schwung-remote-api.js opens its own WebSocket and subscribes to the
/// active Tool, so no guessed native parameter schema is needed.
private struct ToolCustomWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor.clear
        view.scrollView.backgroundColor = UIColor.clear
        view.scrollView.isScrollEnabled = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard uiView.url != url else { return }
        uiView.load(URLRequest(url: url))
    }
}
