import SwiftUI

/// macOS adaptation of the verified iOS SchwungTroller screen.
/// Protocol handling is shared with the v0.8.3-development RemoteControlStore.
struct SchwungTrollerScreen: View {
    @ObservedObject var device: MoveConnection
    @StateObject private var remote = RemoteControlStore()
    @State private var selectedComponent = "synth"
    @State private var showingModulePicker = false
    @AppStorage("SchwungPocketMac.TrollerExpandedSections.v1") private var storedExpandedSections = "mixer,chain,parameters,settings"
    @AppStorage("SchwungPocketMac.TrollerSectionOrder.v1") private var storedSectionOrder = "connection,mixer,chain,parameters,settings"
    @State private var showingMIDILog = false
    @StateObject private var midiActivity = MirrorMIDIActivityStore.shared

    private var currentComponent: String {
        remote.parameters.first?.component ?? selectedComponent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                destinationPicker
                ForEach(orderedSectionKeys, id: \.self) { key in
                    sectionView(key)
                }
                Spacer(minLength: 24)
            }.padding(20).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.background)
        .onAppear { remote.loadSlotModules(address: device.baseAddress); remote.connectIfNeeded(address: device.baseAddress) }
        .onChange(of: device.baseAddress) { address in remote.loadSlotModules(address: address); remote.connectIfNeeded(address: address) }
        .onDisappear { remote.disconnect() }
    }

    private var orderedSectionKeys: [String] {
        let allowed = ["connection", "mixer", "chain", "parameters", "settings"]
        let saved = storedSectionOrder.split(separator: ",").map(String.init).filter { allowed.contains($0) }
        return saved + allowed.filter { !saved.contains($0) }
    }

    @ViewBuilder
    private func sectionView(_ key: String) -> some View {
        switch key {
        case "connection":
            DisclosureGroup(isExpanded: expansion("connection")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(remote.isConnected ? Theme.success : Theme.warning).frame(width: 9, height: 9)
                        Text(remote.statusText).font(.callout.weight(.medium))
                        Spacer()
                        Button("Reconnect") { remote.disconnect(); remote.connect(address: device.baseAddress) }
                            .buttonStyle(.bordered).disabled(remote.isConnected)
                    }
                    Text(device.baseAddress).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                    midiActivityPanel
                }.padding(.top, 8)
            } label: { sectionLabel("Connection and MIDI Activity", symbol: "network") }
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        case "mixer":
            DisclosureGroup(isExpanded: expansion("mixer")) {
                fourSlotMixer.padding(.top, 10)
            } label: { sectionLabel("Four-slot Mixer", symbol: "slider.vertical.3") }
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        case "chain":
            if isSlotDestination {
                DisclosureGroup(isExpanded: expansion("chain")) {
                    VStack(alignment: .leading, spacing: 14) {
                        slotChainPicker
                        Divider().overlay(Color.white.opacity(0.06))
                        moduleSwapSection
                    }.padding(.top, 10)
                } label: { sectionLabel("Signal Chain and Modules", symbol: "point.3.connected.trianglepath.dotted") }
                    .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            } else if remote.destination == .masterFX {
                masterFXModuleSection
            }
        case "parameters":
            if remote.destination == .tool {
                infoCard("Tool controls", detail: "Tool values are shown according to the metadata exposed by Schwung. Unsupported or read-only values are never sent as edits.")
            }
            if remote.destination == .masterFX {
                infoCard("Master FX", detail: "Uses the dedicated Master FX messages and the DSP path discovery/hot-swap logic ported from v0.8.3-development.")
            }
            if remote.isLoadingSlotModules {
                HStack(spacing: 10) { ProgressView(); Text("Discovering installed modules…").foregroundStyle(Theme.muted) }
            }
            if let error = remote.slotModulesError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Theme.warning)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
            DisclosureGroup(isExpanded: expansion("parameters")) {
                VStack(alignment: .leading, spacing: 12) {
                    if !remote.levels.isEmpty { levelPicker }
                    if case .error(let error) = remote.loadState { infoCard("Could not load controls", detail: error) }
                    else if case .unsupported(let reason) = remote.loadState { infoCard("Controls unavailable", detail: reason) }
                    else if remote.parameters.isEmpty { infoCard("Waiting for metadata", detail: "Select a destination and wait for Schwung to report its parameter hierarchy. The app does not invent controls for unknown protocol fields.") }
                    else { parameterSection }
                }.padding(.top, 10)
            } label: { sectionLabel("Parameter Controls", symbol: "dial.low") }
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        case "settings":
            DisclosureGroup(isExpanded: expansion("settings")) {
                VStack(alignment: .leading, spacing: 14) {
                    slotSettings
                    sectionOrderControls
                }.padding(.top, 10)
            } label: { sectionLabel("Slot Settings and Section Order", symbol: "gearshape") }
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        default:
            EmptyView()
        }
    }

    private var midiActivityPanel: some View {
        DisclosureGroup(isExpanded: $showingMIDILog) {
            VStack(alignment: .leading, spacing: 6) {
                if midiActivity.events.isEmpty {
                    Text("Play a note or move a MIDI control to see incoming activity.")
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(midiActivity.events.enumerated()), id: \.offset) { _, event in
                        Text(event).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Text("MIDI Activity").font(.subheadline.weight(.medium))
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let active = midiActivity.lastEventAt.map { context.date.timeIntervalSince($0) < 1.5 } ?? false
                    HStack(spacing: 6) {
                        Circle().fill(active ? Theme.success : Theme.warning).frame(width: 7, height: 7)
                        Text(active ? "MIDI ACTIVE" : "MIDI INACTIVE")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(active ? Theme.success : Theme.warning)
                    }
                }
            }
        }
    }

    private var sectionOrderControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SECTION ORDER").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
            Text("Use the arrows to choose the order of the SchwungTroller panels. Your choice is saved on this Mac.")
                .font(.caption).foregroundStyle(Theme.muted)
            ForEach(orderedSectionKeys, id: \.self) { key in
                let index = orderedSectionKeys.firstIndex(of: key) ?? 0
                HStack(spacing: 10) {
                    Text(sectionTitle(for: key)).font(.callout.weight(.medium))
                    Spacer()
                    Button { moveSection(key, offset: -1) } label: {
                        Image(systemName: "arrow.up").frame(width: 24, height: 24)
                    }.buttonStyle(.bordered).disabled(index == 0)
                    Button { moveSection(key, offset: 1) } label: {
                        Image(systemName: "arrow.down").frame(width: 24, height: 24)
                    }.buttonStyle(.bordered).disabled(index == orderedSectionKeys.count - 1)
                }
            }
        }.padding(12).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(for key: String) -> String {
        switch key {
        case "connection": "Connection and MIDI Activity"
        case "mixer": "Four-slot Mixer"
        case "chain": "Signal Chain and Modules"
        case "parameters": "Parameter Controls"
        default: "Slot Settings and Section Order"
        }
    }

    private func moveSection(_ key: String, offset: Int) {
        var order = orderedSectionKeys
        guard let index = order.firstIndex(of: key) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        storedSectionOrder = order.joined(separator: ",")
    }

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(get: { Set(storedExpandedSections.split(separator: ",").map(String.init)).contains(key) }, set: { value in
            var expanded = Set(storedExpandedSections.split(separator: ",").map(String.init))
            if value { expanded.insert(key) } else { expanded.remove(key) }
            storedExpandedSections = expanded.sorted().joined(separator: ",")
        })
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
    }

    private var fourSlotMixer: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<4, id: \.self) { slot in
                VStack(spacing: 8) {
                    Text(remote.slotInstrumentNames[slot] ?? "Slot \(slot + 1)")
                        .font(.system(size: 10, weight: .heavy)).lineLimit(2).multilineTextAlignment(.center).frame(minHeight: 28)
                    Slider(value: Binding(get: { remote.slotVolume(for: slot) }, set: { remote.setSlotVolume($0, slot: slot) }), in: 0...4)
                        .rotationEffect(.degrees(-90)).frame(width: 110, height: 24).frame(height: 116)
                        .overlay {
                            GeometryReader { g in
                                Rectangle().fill(Theme.muted.opacity(0.65)).frame(width: 1, height: 100)
                                    .position(x: g.size.width / 2, y: g.size.height * 0.75).allowsHitTesting(false)
                            }
                        }
                    Text("\(Int(remote.slotVolume(for: slot) * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.muted)
                    HStack(spacing: 5) {
                        Button { remote.setSlotMuted(!remote.isSlotMuted(slot), slot: slot) } label: {
                            Text(remote.isSlotMuted(slot) ? "MUTED" : "M").font(.system(size: 10, weight: .bold)).frame(maxWidth: .infinity, minHeight: 27)
                                .foregroundStyle(remote.isSlotMuted(slot) ? Theme.background : .white)
                                .background(remote.isSlotMuted(slot) ? Theme.warning : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                        Button { remote.setSlotSoloed(!remote.isSlotSoloed(slot), slot: slot) } label: {
                            Text(remote.isSlotSoloed(slot) ? "SOLO" : "S").font(.system(size: 10, weight: .bold)).frame(maxWidth: .infinity, minHeight: 27)
                                .foregroundStyle(remote.isSlotSoloed(slot) ? Theme.background : .white)
                                .background(remote.isSlotSoloed(slot) ? Theme.violet : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity).padding(8).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SchwungTroller").font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Live knobs and switches built from the instrument’s own metadata.")
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(remote.isConnected ? Theme.success : Theme.warning).frame(width: 8, height: 8)
                Text(remote.statusText).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.surface, in: Capsule())
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DESTINATION").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(RemoteDestination.allCases) { destination in
                    Button { remote.select(destination) } label: {
                        VStack(spacing: 4) {
                            Label(destination.title, systemImage: destination.symbol).font(.system(size: 12, weight: .semibold))
                            if let slot = slotNumber(for: destination) {
                                Text(remote.slotInstrumentNames[slot] ?? "Slot \(slot + 1)").font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(remote.destination == destination ? Theme.background.opacity(0.8) : Theme.muted).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(remote.destination == destination ? Theme.background : Color.white)
                            .background(remote.destination == destination ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var parameterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(remote.currentLevelName.isEmpty ? remote.destination.title : remote.currentLevelName)
                        .font(.headline)
                    Text("\(remote.visibleParameters.count) parameters · \(remote.levels.count) levels")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                if remote.isLoadingSlotModules { ProgressView().controlSize(.small) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(displayedParameters) { parameter in
                    parameterControl(parameter)
                }
            }
        }
    }

    @ViewBuilder
    private func parameterControl(_ parameter: RemoteParameter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(parameter.displayName).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text(remote.displayValue(for: parameter))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            switch parameter.kind {
            case .knob:
                RotaryKnob(
                    label: parameter.displayName,
                    value: remote.currentDouble(for: parameter),
                    range: parameter.minimum...max(parameter.maximum, parameter.minimum),
                    step: parameter.safeStep,
                    valueText: remote.displayValue(for: parameter),
                    tint: Theme.accent,
                    onChange: { remote.setNumeric($0, for: parameter) }
                )
                .frame(maxWidth: 150)
                HStack {
                    Text(parameter.format(parameter.minimum))
                    Spacer()
                    Text(parameter.format(parameter.maximum))
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
            case .choice:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                    ForEach(Array(parameter.options.enumerated()), id: \.offset) { index, option in
                        let selected = remote.currentChoiceIndex(for: parameter) == index
                        Button {
                            remote.setChoice(index, for: parameter)
                        } label: {
                            Text(option)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .padding(.horizontal, 7)
                                .foregroundStyle(selected ? Theme.background : Color.white)
                                .background(selected ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .readOnly(let reason):
                Text(reason).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Color.white.opacity(0.055), lineWidth: 1) }
    }

    private var slotSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SLOT MIX").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                Label("Volume \(Int(remote.slotVolume * 100))%", systemImage: "speaker.wave.2")
                Spacer()
                Button(remote.slotMuted ? "Unmute" : "Mute") {
                    remote.setSlotMuted(!remote.slotMuted)
                }.buttonStyle(.bordered).tint(Theme.accent)
                Button(remote.slotSoloed ? "Unsolo" : "Solo") {
                    remote.setSlotSoloed(!remote.slotSoloed)
                }.buttonStyle(.bordered).tint(Theme.violet)
            }
            Slider(value: Binding(get: { remote.slotVolume }, set: { remote.setSlotVolume($0) }), in: 0...4)
                .tint(Theme.accent)
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var moduleSwapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installed modules").font(.headline)
                    Text("MIDI FX → Instrument → Audio FX 1 → Audio FX 2").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Refresh") { remote.loadSlotModules(address: device.baseAddress) }.buttonStyle(.bordered).tint(Theme.accent)
            }
            ForEach(["midi_fx1", "synth", "fx1", "fx2"], id: \.self) { component in
                let expected = component == "synth" ? "sound_generator" : (component.hasPrefix("midi_fx") ? "midi_fx" : "audio_fx")
                let compatible = remote.availableSlotModules.filter { $0.componentType == expected && !$0.deviceOnly }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(component == "synth" ? "Instrument" : (component == "midi_fx1" ? "MIDI" : "Audio FX \(component == "fx1" ? "1" : "2")"))
                            .font(.system(size: 10, weight: .bold))
                        Text(remote.componentNames[component] ?? "Empty").font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Menu("Install / Swap") {
                        ForEach(compatible) { item in
                            Button(item.name) { remote.swapModule(component: component, moduleID: item.id) }
                        }
                    }.font(.system(size: 10, weight: .semibold)).tint(Theme.accent).disabled(compatible.isEmpty)
                }.padding(10).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            }
        }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var masterFXModuleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Master FX chain").font(.headline)
                    Text("Choose a chain position, then swap an installed audio effect.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Refresh") { remote.loadSlotModules(address: device.baseAddress) }
                    .buttonStyle(.bordered).tint(Theme.accent)
            }
            Picker("Effect position", selection: $remote.selectedMasterFXComponent) {
                ForEach(1...max(remote.masterFXCapacity, 4), id: \.self) { index in
                    Text("FX \(index)").tag("master_fx:fx\(index)")
                }
            }.pickerStyle(.segmented)
            let effects = remote.availableSlotModules.filter { $0.componentType == "audio_fx" && !$0.deviceOnly }
            if effects.isEmpty {
                Text("No compatible audio effects discovered yet.")
                    .font(.callout).foregroundStyle(Theme.muted)
            } else {
                Menu("Swap selected effect…") {
                    ForEach(effects) { module in
                        Button(module.name) {
                            remote.swapMasterFXModule(component: remote.selectedMasterFXComponent, moduleID: module.id)
                        }
                    }
                }.tint(Theme.accent)
            }
            Button("Clear selected effect") {
                remote.clearMasterFXModule(component: remote.selectedMasterFXComponent)
            }
            .buttonStyle(.bordered).tint(Theme.warning)
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PARAMETER GROUP").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
            Picker("Parameter group", selection: $remote.selectedLevelID) {
                ForEach(remote.levels) { level in Text(level.name).tag(level.id) }
            }.pickerStyle(.menu).tint(Theme.accent)
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func slotNumber(for destination: RemoteDestination) -> Int? {
        switch destination {
        case .slot1: return 0
        case .slot2: return 1
        case .slot3: return 2
        case .slot4: return 3
        case .masterFX, .tool: return nil
        }
    }

    private var slotChainPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(["midi_fx1", "synth", "fx1", "fx2"], id: \.self) { component in
                    let title = component == "synth" ? "Instrument" : (component == "midi_fx1" ? "MIDI" : "Audio FX \(component == "fx1" ? "1" : "2")")
                    let selected = selectedComponent == component
                    let loaded = remote.componentNames[component] != nil
                    let bypassed = remote.isComponentBypassed(component)
                    HStack(alignment: .top, spacing: 8) {
                        Button { selectedComponent = component } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                                Text(remote.componentNames[component] ?? "Empty").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).foregroundStyle(.white)
                        }.buttonStyle(.plain)
                        VStack(alignment: .trailing, spacing: 7) {
                            HStack(spacing: 4) {
                                Circle().fill(loaded && !bypassed ? Theme.success : Theme.warning).frame(width: 6, height: 6)
                                Text(!loaded ? "EMPTY" : (bypassed ? "OFF" : "ON"))
                                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(!loaded || bypassed ? Theme.warning : Theme.success)
                            }
                            Button { remote.setComponentBypassed(component, bypassed: !bypassed) } label: {
                                Label(bypassed ? "Enable" : "Bypass", systemImage: bypassed ? "power" : "pause.circle")
                                    .font(.system(size: 10, weight: .semibold))
                            }.buttonStyle(.bordered).tint(bypassed ? Theme.success : Theme.accent).disabled(!remote.isConnected || !loaded)
                            Button { remote.clearSlotModule(component: component) } label: {
                                Label("Clear", systemImage: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                            }.buttonStyle(.bordered).tint(Theme.warning).disabled(!remote.isConnected || !loaded)
                        }.fixedSize(horizontal: true, vertical: true)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1) }
                }
            }
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var displayedParameters: [RemoteParameter] {
        if remote.destination == .masterFX {
            return remote.parameters.filter { $0.component == remote.selectedMasterFXComponent }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        if remote.destination == .tool { return [] }
        if selectedComponent == "synth" {
            return remote.visibleParameters.filter { $0.component == "synth" }
        }
        return remote.parameters.filter { $0.component == selectedComponent }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var isSlotDestination: Bool {
        [.slot1, .slot2, .slot3, .slot4].contains(remote.destination)
    }

    private func infoCard(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(Theme.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 15))
    }
}
