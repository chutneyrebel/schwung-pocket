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

private enum TrollerSection: String, CaseIterable, Identifiable {
    case connection, mixer, signalChain, parameters, slotSettings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .connection: return "Connection & MIDI Activity"
        case .mixer: return "Performance Mixer"
        case .signalChain: return "Signal Chain & Installed Modules"
        case .parameters: return "Parameter Controls"
        case .slotSettings: return "Slot Settings"
        }
    }
    var symbol: String {
        switch self {
        case .connection: return "dot.radiowaves.left.and.right"
        case .mixer: return "slider.vertical.3"
        case .signalChain: return "point.3.connected.trianglepath.dotted"
        case .parameters: return "dial.low"
        case .slotSettings: return "gearshape"
        }
    }
}

/// SchwungTroller module: destination selector + metadata-driven parameter controls.
struct NativeControlsScreen: View {
    @ObservedObject var device: MoveConnectionStore
    @StateObject private var remote = RemoteControlStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedChainComponent: SchwungChainComponent = .instrument
    @State private var showingModulePicker = false
    @State private var showingClearConfirmation = false
    @State private var pendingMasterFXClearComponent: String?
    @State private var showingMIDILog = false
    @StateObject private var midiActivity = MirrorMIDIActivityStore.shared
    @AppStorage("SchwungPocket.TrollerSectionOrder.v1") private var storedSectionOrder = "mixer,signalChain,parameters,connection,slotSettings"
    @AppStorage("SchwungPocket.TrollerCollapsedSections.v1") private var storedCollapsedSections = "connection,signalChain,parameters,slotSettings"

    var body: some View {
        ModuleScreenShell(
            eyebrow: "SCHWUNG POCKET / LIVE INSTRUMENT",
            title: "SchwungTroller",
            subtitle: "Four-slot performance control with a focused signal chain and live parameters."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                performanceStatusStrip

                destinationCard

                ForEach(orderedSections.filter { $0 != .mixer }) { section in
                    if shouldShow(section) {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { !collapsedSections.contains(section.rawValue) },
                                set: { expanded in setSection(section, expanded: expanded) }
                            )
                        ) {
                            sectionContent(section)
                                .padding(.top, 9)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(sectionSummary(section))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .tint(Theme.accent)
                        .padding(13)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
                        }
                    }
                }
            }
        }
        .onAppear {
            remote.loadSlotModules(address: device.addressText)
            // The screen stays mounted after its first visit, so this is normally a no-op.
            // It reconnects only if the screen was disconnected or the Move address changed.
            remote.connectIfNeeded(address: device.addressText)
        }
        .onChange(of: device.addressText) { newAddress in
            remote.connectIfNeeded(address: newAddress)
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
        .confirmationDialog(
            "Clear Master FX position?",
            isPresented: Binding(
                get: { pendingMasterFXClearComponent != nil },
                set: { if !$0 { pendingMasterFXClearComponent = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let component = pendingMasterFXClearComponent {
                Button("Clear Effect", role: .destructive) {
                    remote.clearMasterFXModule(component: component)
                    pendingMasterFXClearComponent = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingMasterFXClearComponent = nil }
        } message: {
            Text("This unloads the effect from that Master FX chain position.")
        }
    }

    private var performanceStatusStrip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(remote.isConnected ? 0.35 : 0), radius: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(remote.statusText.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(remote.isConnected ? "Move control link" : "Check your Move connection below")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !midiActivity.events.isEmpty {
                HStack(spacing: 5) {
                    Circle().fill(Theme.success).frame(width: 6, height: 6)
                    Text("MIDI")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(Theme.success)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.success.opacity(0.10), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }
            Text(remote.destination.title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.accent.opacity(0.10), in: Capsule())
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: remote.destination)
        .animation(.easeOut(duration: 0.18), value: midiActivity.events.isEmpty)
    }

    private func sectionSummary(_ section: TrollerSection) -> String {
        switch section {
        case .connection:
            return midiActivity.events.isEmpty ? "Link status and incoming MIDI" : "\(midiActivity.events.count) recent MIDI events"
        case .mixer:
            return "Four independent slot levels"
        case .signalChain:
            if isMasterFX {
                let loaded = (1...max(remote.masterFXCapacity, 1)).filter {
                    remote.componentNames["master_fx:fx\($0)"] != nil
                }.count
                return "\(loaded)/\(max(remote.masterFXCapacity, 1)) Master FX loaded"
            }
            let loaded = chainComponents.filter { remote.componentNames[$0.rawValue] != nil }.count
            return "\(loaded)/\(chainComponents.count) modules loaded"
        case .parameters:
            return selectedComponentParameters.isEmpty
                ? "Waiting for reported controls"
                : "\(selectedComponentParameters.count) live controls · \(selectedChainComponent.title)"
        case .slotSettings:
            return "Current slot options"
        }
    }

    private var orderedSections: [TrollerSection] {
        let saved = storedSectionOrder.split(separator: ",")
            .compactMap { TrollerSection(rawValue: String($0)) }
            .filter { $0 != .mixer }
        return [.mixer] + saved + TrollerSection.allCases.filter { $0 != .mixer && !saved.contains($0) }
    }

    private var collapsedSections: Set<String> {
        Set(storedCollapsedSections.split(separator: ",").map(String.init))
    }

    private func setSection(_ section: TrollerSection, expanded: Bool) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            var collapsed = collapsedSections
            if expanded { collapsed.remove(section.rawValue) }
            else { collapsed.insert(section.rawValue) }
            storedCollapsedSections = TrollerSection.allCases
                .filter { collapsed.contains($0.rawValue) }
                .map(\.rawValue)
                .joined(separator: ",")
        }
    }

    private func shouldShow(_ section: TrollerSection) -> Bool {
        switch section {
        case .connection, .mixer: return true
        case .signalChain: return isInstrumentSlot || isMasterFX
        case .parameters: return true
        case .slotSettings: return isInstrumentSlot
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: TrollerSection) -> some View {
        switch section {
        case .connection:
            connectionCard
        case .mixer:
            destinationCard
        case .signalChain:
            if isInstrumentSlot { slotChainCard }
            else if isMasterFX { masterFXCard }
        case .parameters:
            if isInstrumentSlot { parameterGroupCard }
            contentSection
        case .slotSettings:
            slotSettingsCard
        }
    }

    // MARK: Connection

    private var connectionCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(remote.statusText)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    switch remote.connection {
                    case .connected, .connecting, .reconnecting:
                        Button { remote.disconnect() } label: {
                            Label("Disconnect", systemImage: "xmark.circle.fill").font(.system(size: 11, weight: .bold))
                        }.buttonStyle(StudioSecondaryButton())
                    case .disconnected, .failed:
                        Button { remote.connect(address: device.addressText) } label: {
                            Label("Connect", systemImage: "dot.radiowaves.left.and.right").font(.system(size: 11, weight: .bold))
                        }.buttonStyle(StudioPrimaryButton())
                    }
                    if remote.isConnected {
                        Button { remote.refresh() } label: {
                            Label("Reload", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        }.buttonStyle(StudioSecondaryButton())
                    }
                    Spacer(minLength: 0)
                }
                DisclosureGroup(isExpanded: $showingMIDILog) {
                    midiActivityContent
                        .padding(.top, 5)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(midiActivity.events.isEmpty ? Theme.muted : Theme.success)
                            .frame(width: 7, height: 7)
                        Text("Live Move Note / CC Log")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Spacer()
                        if !midiActivity.events.isEmpty {
                            Text("MIDI ACTIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.success)
                        }
                    }
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
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("PERFORMANCE MIXER")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.35)
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    Text("0–400%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
                HStack {
                    Text("REMOTE DESTINATION").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(remote.instrumentName.isEmpty ? " " : remote.instrumentName)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent).lineLimit(1)
                }
                DestinationSelector(
                    selection: remote.destination,
                    isConnected: remote.isConnected,
                    slotInstrumentNames: remote.slotInstrumentNames,
                    slotVolume: remote.slotVolume(for:),
                    isMuted: remote.isSlotMuted,
                    isSoloed: remote.isSlotSoloed,
                    onVolumeChange: { slot, volume in remote.setSlotVolume(volume, slot: slot) },
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

    private var midiActivityContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: midiActivity.events.isEmpty ? "waveform.path" : "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(midiActivity.events.isEmpty ? Theme.muted : Theme.success)
                Text(midiActivity.events.isEmpty ? "Waiting for Move events" : "Recent event stream")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                Text("\(midiActivity.events.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(midiActivity.events.isEmpty ? Theme.muted : Theme.success)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background((midiActivity.events.isEmpty ? Theme.muted : Theme.success).opacity(0.10), in: Capsule())
            }

            if midiActivity.events.isEmpty {
                Text("Play a pad or move a physical control on Move. Recent note and CC events captured by Mirror will appear here.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(midiActivity.events.enumerated()), id: \.offset) { index, event in
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.success.opacity(index == 0 ? 0.95 : 0.35))
                                .frame(width: 3)
                            Text(event)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(.top, 2)
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
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(chainComponents) { component in
                        let selected = selectedChainComponent == component
                        let moduleName = remote.componentNames[component.rawValue]
                        VStack(alignment: .leading, spacing: 7) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    selectedChainComponent = component
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(moduleName == nil ? Theme.muted : (remote.isComponentBypassed(component.rawValue) ? Theme.warning : Theme.success))
                                            .frame(width: 6, height: 6)
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
                                    HStack(spacing: 5) {
                                        Image(systemName: moduleName == nil ? "circle.dashed" : (remote.isComponentBypassed(component.rawValue) ? "pause.circle.fill" : "checkmark.circle.fill"))
                                            .font(.system(size: 9, weight: .semibold))
                                        Text(moduleName == nil ? "EMPTY POSITION" : (remote.isComponentBypassed(component.rawValue) ? "BYPASSED" : "ACTIVE"))
                                            .font(.system(size: 8, weight: .heavy))
                                            .tracking(0.7)
                                    }
                                    .foregroundStyle(moduleName == nil ? Theme.muted : (remote.isComponentBypassed(component.rawValue) ? Theme.warning : Theme.success))
                                }
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: 39, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            HStack(spacing: 8) {
                                Button {
                                    remote.setComponentBypassed(
                                        component.rawValue,
                                        bypassed: !remote.isComponentBypassed(component.rawValue)
                                    )
                                } label: {
                                    Text(remote.isComponentBypassed(component.rawValue) ? "Enable" : "Bypass")
                                        .font(.system(size: 9, weight: .bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .frame(maxWidth: .infinity, minHeight: 25)
                                }
                                .buttonStyle(StudioSecondaryButton())
                                .disabled(!remote.isConnected || moduleName == nil)
                                Button {
                                    selectedChainComponent = component
                                    showingClearConfirmation = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.warning)
                                        .frame(width: 30, height: 25)
                                        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear \(component.title)")
                                .disabled(!remote.isConnected || moduleName == nil)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Theme.accent.opacity(0.09) : Theme.surfaceRaised)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
                        }
                        .animation(.easeOut(duration: 0.16), value: selected)
                        .accessibilityElement(children: .contain)
                    }
                }


            }
        }
    }

    private var parameterGroupCard: some View {
        Group {
            if selectedChainComponent == .instrument && remote.levels.count > 1 {
                PocketCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("PARAMETER GROUP")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(Theme.muted)
                        Picker("Instrument parameter group", selection: $remote.selectedLevelID) {
                            ForEach(remote.levels) { level in Text(level.name).tag(level.id) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }
                }
            } else if selectedChainComponent != .instrument {
                PocketCard {
                    Text("Controls for \(selectedChainComponent.title) appear below when Schwung reports editable parameters.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var resolvedToolCustomUIURL: URL? {
        guard isTool, let raw = remote.customToolUIURL, !raw.isEmpty else { return nil }
        return resolveCustomUIURL(raw, component: "tool", mode: "tool")
    }

    private var resolvedSelectedMasterFXCustomUIURL: URL? {
        guard isMasterFX,
              let raw = remote.customComponentUIURLs[remote.selectedMasterFXComponent],
              !raw.isEmpty else { return nil }
        return resolveCustomUIURL(raw, component: remote.selectedMasterFXComponent, mode: "master_fx")
    }

    /// Resolve a Manager-provided panel on the Move's own host. Protocol URLs
    /// may be relative paths, but must never redirect the initial load to an
    /// unrelated host supplied by module metadata.
    private func resolveCustomUIURL(_ raw: String, component: String, mode: String) -> URL? {
        let address = device.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        let baseText = address.contains("://") ? address : "https://" + address
        guard let baseURL = URL(string: baseText),
              let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = baseComponents.scheme,
              let host = baseComponents.host,
              let rawURL = URL(string: raw),
              var target = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) else { return nil }
        if target.scheme == nil {
            target = URLComponents(url: URL(string: raw, relativeTo: baseURL)?.absoluteURL ?? baseURL,
                                   resolvingAgainstBaseURL: false) ?? target
        }
        guard target.host == nil || target.host?.caseInsensitiveCompare(host) == .orderedSame else { return nil }
        target.scheme = scheme
        target.host = host
        target.port = baseComponents.port
        var items = target.queryItems ?? []
        items.removeAll { ["schwungStandalone", "tool", "master_fx", "component"].contains($0.name) }
        items.append(URLQueryItem(name: "schwungStandalone", value: "1"))
        items.append(URLQueryItem(name: mode, value: "1"))
        items.append(URLQueryItem(name: "component", value: component))
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
            // Tool state arrives as untyped values, not editable parameter
            // metadata. Keep it in the live state readout instead of rendering
            // every state field as a disabled control with a warning.
            return []
        }
        if selectedChainComponent == .instrument {
            return remote.visibleParameters.filter { $0.component == selectedChainComponent.rawValue }
        }
        return remote.parameters
            .filter { $0.component == selectedChainComponent.rawValue }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func formattedToolStateValue(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return raw
        }
        if let state = object as? [String: Any] {
            var parts: [String] = []
            if let op = state["op"] as? String { parts.append("op: \(op)") }
            if let owner = state["owner"] { parts.append("owner: \(owner)") }
            if let rawNotes = state["notes"] as? [NSNumber] {
                let notes = rawNotes.map { number -> String in
                    let note = number.intValue
                    return "\(note) (\(midiNoteName(note)))"
                }
                parts.append("notes: \(notes.joined(separator: ", "))")
            }
            for key in ["velocity", "route", "channel", "cc", "controller", "midi_cc"] {
                guard let value = state[key] else { continue }
                if key == "channel", let number = value as? NSNumber, (0...15).contains(number.intValue) {
                    parts.append("MIDI channel: \(number.intValue + 1)")
                } else if ["cc", "controller", "midi_cc"].contains(key) {
                    parts.append("CC \(value)")
                } else {
                    parts.append("\(key.replacingOccurrences(of: "_", with: " ")): \(value)")
                }
            }
            for key in state.keys.sorted() where !["op", "owner", "notes", "velocity", "route", "channel", "cc", "controller", "midi_cc"].contains(key) {
                if let value = state[key] { parts.append("\(key): \(value)") }
            }
            if !parts.isEmpty { return parts.joined(separator: "  ·  ") }
        }
        guard JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return text
    }

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        guard (0...127).contains(note) else { return "note \(note)" }
        return "\(names[note % 12])\((note / 12) - 1)"
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
                let toolStateKeys = remote.values.keys.filter { $0.hasPrefix("overtake_dsp:") }.sorted()
                if !toolStateKeys.isEmpty {
                    Text("LIVE TOOL STATE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.muted)
                    ForEach(toolStateKeys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(key.dropFirst("overtake_dsp:".count)).replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.muted)
                            Text(formattedToolStateValue(remote.values[key] ?? ""))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(9)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    Button {
                        pendingMasterFXClearComponent = remote.selectedMasterFXComponent
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(StudioSecondaryButton())
                    .disabled(!remote.isConnected || remote.componentNames[remote.selectedMasterFXComponent] == nil)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(1...max(remote.masterFXCapacity, 1), id: \.self) { index in
                        let key = "master_fx:fx\(index)"
                        let moduleName = remote.componentNames[key]
                        let selected = remote.selectedMasterFXComponent == key
                        HStack(spacing: 6) {
                            Button {
                                remote.selectedMasterFXComponent = key
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(moduleName == nil ? Theme.muted : (remote.isComponentBypassed(key) ? Theme.warning : Theme.success))
                                            .frame(width: 6, height: 6)
                                        Text("Master FX \(index)")
                                            .font(.system(size: 12, weight: .bold))
                                    }
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
                if let error = remote.slotModulesError {
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(remote.isComponentBypassed(remote.selectedMasterFXComponent) ? "MODULE BYPASSED" : "MODULE ACTIVE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(remote.isComponentBypassed(remote.selectedMasterFXComponent) ? Theme.warning : Theme.success)
                        Text(remote.componentNames[remote.selectedMasterFXComponent] ?? "No effect in this position")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button {
                        remote.setComponentBypassed(
                            remote.selectedMasterFXComponent,
                            bypassed: !remote.isComponentBypassed(remote.selectedMasterFXComponent)
                        )
                    } label: {
                        Label(
                            remote.isComponentBypassed(remote.selectedMasterFXComponent) ? "Enable" : "Bypass",
                            systemImage: remote.isComponentBypassed(remote.selectedMasterFXComponent) ? "play.fill" : "pause.fill"
                        )
                        .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(StudioSecondaryButton())
                    .disabled(!remote.isConnected || remote.componentNames[remote.selectedMasterFXComponent] == nil)
                }
            }
        }
    }

    // MARK: Slot settings

    private var slotSettingsCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("SLOT SETTINGS")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    Text(remote.destination.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Output level", systemImage: "speaker.wave.2")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Spacer()
                        Text("\(Int((remote.slotVolume * 100).rounded()))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
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
                    .accessibilityLabel("Slot output level")
                    .accessibilityValue("\(Int((remote.slotVolume * 100).rounded())) percent")
                    .disabled(!remote.isConnected || !isInstrumentSlot)

                    HStack {
                        Text("0%")
                        Spacer()
                        Text("Normal")
                        Spacer()
                        Text("400%")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.muted)
                }
                .padding(11)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("PLAYBACK")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.muted)

                    Toggle(isOn: Binding(
                        get: { remote.slotMuted },
                        set: { remote.setSlotMuted($0) }
                    )) {
                        Label("Mute slot", systemImage: "speaker.slash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .tint(Theme.accent)
                    .disabled(!remote.isConnected || !isInstrumentSlot)

                    settingDivider

                    Toggle(isOn: Binding(
                        get: { remote.slotSoloed },
                        set: { remote.setSlotSoloed($0) }
                    )) {
                        Label("Solo slot", systemImage: "headphones")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .tint(Theme.accent)
                    .disabled(!remote.isConnected || !isInstrumentSlot)
                }
                .padding(11)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("MIDI ROUTING")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.muted)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Receive channel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
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

                    settingDivider

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Forward channel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
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
                }
                .padding(11)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                if !remote.isConnected {
                    Label("Connect to Move to edit these settings.", systemImage: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !isInstrumentSlot {
                    Label("These settings apply to Slots 1–4. Master FX and Tool use separate controls.", systemImage: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
                    if resolvedSelectedMasterFXCustomUIURL == nil {
                        let moduleName = remote.componentNames[remote.selectedMasterFXComponent]
                        let advertisedPanel = remote.customComponentUIURLs[remote.selectedMasterFXComponent] != nil
                        let emptyText = moduleName == nil
                            ? "This Master FX position is empty. Load an effect on Move, then tap Reload."
                            : (advertisedPanel
                                ? "Schwung reports \(moduleName ?? "this effect") and advertises a custom panel, but its URL could not be resolved safely. Check the Move address in Settings."
                                : "Schwung reports \(moduleName ?? "this effect"), but returned no parameter metadata or custom panel for it.")
                        messageCard(icon: "square.dashed", title: "No Master FX controls", text: emptyText)
                    }
                } else if isTool {
                    // Tool state is shown as read-only live data in toolInfoCard.
                    // Only show this fallback when neither a custom panel nor
                    // state values are available.
                    let hasToolState = remote.values.keys.contains { $0.hasPrefix("overtake_dsp:") }
                    if resolvedToolCustomUIURL == nil && !hasToolState {
                        let emptyText = remote.instrumentName.isEmpty
                            ? "No overtake Tool is currently loaded. Load a Tool in Schwung on Move, then tap Reload."
                            : (remote.customToolUIURL == nil
                                ? "Tool \(remote.instrumentName) has not reported state values and does not advertise a custom web UI."
                                : "Tool \(remote.instrumentName) has no state values, and its advertised custom panel could not be opened.")
                        messageCard(icon: "wrench.and.screwdriver", title: "No native Tool controls", text: emptyText)
                    }
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
        customUICard(url, title: "TOOL CUSTOM PANEL")
    }

    private func customUICard(_ url: URL, title: String) -> some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .foregroundStyle(Theme.accent)
                    Text(title)
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
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedChainComponent.title.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.3)
                            .foregroundStyle(Theme.accent)
                        Text("\(visible.count) reported control\(visible.count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 4)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.success.opacity(0.10), in: Capsule())
                }
                if !knobs.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8, alignment: .top)], alignment: .center, spacing: 14) {
                        ForEach(knobs) { parameter in knob(for: parameter) }
                    }
                }
                ForEach(others) { parameter in ParameterRow(parameter: parameter, remote: remote) }
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
    let slotInstrumentNames: [Int: String]
    let slotVolume: (Int) -> Double
    let isMuted: (Int) -> Bool
    let isSoloed: (Int) -> Bool
    let onVolumeChange: (Int, Double) -> Void
    let onMuteToggle: (Int, Bool) -> Void
    let onSoloToggle: (Int, Bool) -> Void
    let onSelect: (RemoteDestination) -> Void

    private func wireSlot(for destination: RemoteDestination) -> Int? {
        switch destination {
        case .slot1: return 0
        case .slot2: return 1
        case .slot3: return 2
        case .slot4: return 3
        case .masterFX, .tool: return nil
        }
    }

    private var slotDestinations: [RemoteDestination] {
        [.slot1, .slot2, .slot3, .slot4]
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .top, spacing: 5) {
                ForEach(slotDestinations) { destination in
                    let slot = wireSlot(for: destination)!
                    let isSelected = destination == selection
                    VStack(spacing: 5) {
                        Button { onSelect(destination) } label: {
                            VStack(spacing: 3) {
                                Text("S\(slot + 1)")
                                    .font(.system(size: 11, weight: .heavy))
                                Text(slotInstrumentNames[slot] ?? "Slot \(slot + 1)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(slotInstrumentNames[slot] ?? "Slot \(slot + 1)")
                        VerticalVolumeSlider(
                            value: Binding(
                                get: { slotVolume(slot) },
                                set: { onVolumeChange(slot, $0) }
                            ),
                            isEnabled: isConnected
                        )
                        .frame(height: 100)
                        Text("\(Int((slotVolume(slot) * 100).rounded()))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(slotVolume(slot) >= 1 ? Theme.accent : Theme.muted)
                        HStack(spacing: 5) {
                            Button { onMuteToggle(slot, !isMuted(slot)) } label: {
                                Text("M").font(.system(size: 10, weight: .heavy))
                                    .frame(maxWidth: .infinity, minHeight: 23)
                                    .foregroundStyle(isMuted(slot) ? Color.white : Theme.muted)
                                    .background(isMuted(slot) ? Theme.warning : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Slot \(slot + 1) mute")
                            Button { onSoloToggle(slot, !isSoloed(slot)) } label: {
                                Text("S").font(.system(size: 10, weight: .heavy))
                                    .frame(maxWidth: .infinity, minHeight: 23)
                                    .foregroundStyle(isSoloed(slot) ? Theme.background : Theme.muted)
                                    .background(isSoloed(slot) ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Slot \(slot + 1) solo")
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? Theme.accent.opacity(0.13) : Theme.surfaceRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.06), lineWidth: 1)
                    }
                }
            }
            HStack(spacing: 7) {
                ForEach([RemoteDestination.masterFX, .tool]) { destination in
                    let isSelected = destination == selection
                    Button { onSelect(destination) } label: {
                        Label(destination.title, systemImage: destination.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(isSelected ? Theme.accent.opacity(0.22) : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.06), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct VerticalVolumeSlider: View {
    @Binding var value: Double
    let isEnabled: Bool

    var body: some View {
        GeometryReader { geometry in
            let height = max(geometry.size.height - 12, 1)
            let normalized = min(max(value / 4, 0), 1)
            let thumbY = 6 + (1 - normalized) * height
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Theme.surfaceRaised)
                    .frame(width: 7, height: height)
                    .position(x: geometry.size.width / 2, y: 6 + height / 2)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 7, height: max(2, normalized * height))
                    .position(
                        x: geometry.size.width / 2,
                        y: 6 + height - max(2, normalized * height) / 2
                    )
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 22, height: 2)
                    .position(x: geometry.size.width / 2, y: 6 + height * 0.75)
                    .allowsHitTesting(false)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                    .position(x: geometry.size.width / 2, y: thumbY)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let fraction = min(max(1 - ((drag.location.y - 6) / height), 0), 1)
                        let stepped = (fraction * 4 / 0.05).rounded() * 0.05
                        value = min(max(stepped, 0), 4)
                    }
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .accessibilityElement()
        .accessibilityLabel("Slot volume")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: value = min(4, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }
}


private struct ModuleSwapGroup: Identifiable {
    let title: String
    let modules: [RemoteSlotModule]
    var id: String { title }
}

private struct ModuleSwapSheet: View {
    @ObservedObject var remote: RemoteControlStore
    let address: String
    let component: SchwungChainComponent?
    let masterFXComponent: String?
    @Environment(\.dismiss) private var dismiss
    @State private var pendingModule: RemoteSlotModule?
    @State private var searchText = ""

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
            .filter {
                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.id.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                let categoryOrder = $0.subcategoryTitle.localizedCaseInsensitiveCompare($1.subcategoryTitle)
                if categoryOrder != .orderedSame { return categoryOrder == .orderedAscending }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var groupedChoices: [ModuleSwapGroup] {
        let grouped = Dictionary(grouping: choices, by: \.subcategoryTitle)
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { title in
                guard let modules = grouped[title], !modules.isEmpty else { return nil }
                return ModuleSwapGroup(title: title, modules: modules)
            }
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
                if choices.isEmpty {
                    Section("Installed \(displayTitle)") {
                        Text(searchText.isEmpty
                             ? "No compatible modules found. Check that Schwung supports /api/slot-modules and try again."
                             : "No modules match “\(searchText)”. Try another name or module ID.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                } else {
                    ForEach(groupedChoices) { group in
                        Section("\(displayTitle) · \(group.title)") {
                            ForEach(group.modules) { module in
                                Button {
                                    pendingModule = module
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: module.id == pendingModule?.id ? "checkmark.circle.fill" : "waveform")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(module.id == pendingModule?.id ? Color.accentColor : .secondary)
                                            .frame(width: 28, height: 28)
                                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(module.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(module.id)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 4)
                                        if module.id == pendingModule?.id {
                                            Text("SELECTED")
                                                .font(.system(size: 8, weight: .heavy))
                                                .tracking(0.6)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Swap \(displayTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Find a module")
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
        .padding(11)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var choicePicker: some View {
        let selectedIndex = remote.currentChoiceIndex(for: parameter)
        let columnCount = verticalSizeClass == .compact ? 8 : 5
        if parameter.options.isEmpty {
            Text("No options reported by Schwung.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount),
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(Array(parameter.options.enumerated()), id: \.offset) { item in
                    let isSelected = selectedIndex == item.offset
                    Button {
                        remote.setChoice(item.offset, for: parameter)
                    } label: {
                        Text(item.element)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(isSelected ? Theme.accent : Color.white)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(isSelected ? Theme.accent.opacity(0.16) : Theme.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.08), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(parameter.displayName): \(item.element)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
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
