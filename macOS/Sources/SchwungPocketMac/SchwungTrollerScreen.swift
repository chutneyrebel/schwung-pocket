import SwiftUI

/// macOS adaptation of the verified iOS SchwungTroller screen.
/// Protocol handling is shared with the v0.8.3-development RemoteControlStore.
struct SchwungTrollerScreen: View {
    @ObservedObject var device: MoveConnection
    @StateObject private var remote = RemoteControlStore()
    @State private var selectedComponent = "synth"
    @State private var showingModulePicker = false

    private var currentComponent: String {
        remote.parameters.first?.component ?? selectedComponent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                destinationPicker
                if isSlotDestination { slotChainPicker }
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
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(Theme.warning)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                }
                if isSlotDestination {
                    moduleSwapSection
                } else if remote.destination == .masterFX {
                    masterFXModuleSection
                }
                if !remote.levels.isEmpty {
                    levelPicker
                }
                if case .error(let error) = remote.loadState {
                    infoCard("Could not load controls", detail: error)
                } else if case .unsupported(let reason) = remote.loadState {
                    infoCard("Controls unavailable", detail: reason)
                } else if remote.parameters.isEmpty {
                    infoCard("Waiting for metadata", detail: "Select a destination and wait for Schwung to report its parameter hierarchy. The app does not invent controls for unknown protocol fields.")
                } else {
                    parameterSection
                }
                Spacer(minLength: 24)
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.background)
        .onAppear {
            remote.loadSlotModules(address: device.baseAddress)
            if remote.connection == .disconnected { remote.connect(address: device.baseAddress) }
        }
        .onChange(of: device.baseAddress) { address in
            remote.disconnect()
            remote.loadSlotModules(address: address)
            remote.connect(address: address)
        }
        .onDisappear { remote.disconnect() }
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
                    Button {
                        remote.select(destination)
                    } label: {
                        VStack(spacing: 4) {
                            Label(destination.title, systemImage: destination.symbol)
                                .font(.system(size: 12, weight: .semibold))
                            if let slot = slotNumber(for: destination) {
                                Text(remote.slotInstrumentNames[slot] ?? "Slot \(slot + 1)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(remote.destination == destination ? Theme.background.opacity(0.8) : Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(remote.destination == destination ? Theme.background : Color.white)
                        .background(remote.destination == destination ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            if remote.isConnected {
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { slot in
                        VStack(spacing: 6) {
                            Text(remote.slotInstrumentNames[slot] ?? "Slot \(slot + 1)")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(Theme.muted)
                            HStack(spacing: 5) {
                                Button {
                                    remote.setSlotMuted(!remote.isSlotMuted(slot), slot: slot)
                                } label: {
                                    Text(remote.isSlotMuted(slot) ? "MUTED" : "M")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 27)
                                        .foregroundStyle(remote.isSlotMuted(slot) ? Theme.background : Color.white)
                                        .background(remote.isSlotMuted(slot) ? Theme.warning : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain)
                                Button {
                                    remote.setSlotSoloed(!remote.isSlotSoloed(slot), slot: slot)
                                } label: {
                                    Text(remote.isSlotSoloed(slot) ? "SOLO" : "S")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 27)
                                        .foregroundStyle(remote.isSlotSoloed(slot) ? Theme.background : Color.white)
                                        .background(remote.isSlotSoloed(slot) ? Theme.violet : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain)
                            }
                            Text("\(Int(remote.slotVolume(for: slot) * 100))%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Theme.muted.opacity(0.55)).frame(width: 1, height: 12)
                                        .offset(x: geometry.size.width * 0.25)
                                    Slider(value: Binding(
                                        get: { remote.slotVolume(for: slot) },
                                        set: { remote.setSlotVolume($0, slot: slot) }
                                    ), in: 0...4)
                                    .tint(Theme.accent)
                                }
                            }
                            .frame(height: 20)
                            HStack {
                                Text("0")
                                Spacer()
                                Text("100%")
                                Spacer()
                                Text("400%")
                            }.font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
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
                    Text("MIDI FX → Instrument → Audio FX 1 → Audio FX 2")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Refresh") { remote.loadSlotModules(address: device.baseAddress) }
                    .buttonStyle(.bordered).tint(Theme.accent)
            }
            let components = ["midi_fx1", "synth", "fx1", "fx2"]
            HStack(alignment: .top, spacing: 8) {
                ForEach(components, id: \.self) { component in
                    let expected = component == "synth" ? "sound_generator" : (component.hasPrefix("midi_fx") ? "midi_fx" : "audio_fx")
                    let compatible = remote.availableSlotModules.filter { $0.componentType == expected && !$0.deviceOnly }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(component == "synth" ? "Instrument" : (component == "midi_fx1" ? "MIDI" : "Audio FX \(component == "fx1" ? "1" : "2")"))
                            .font(.system(size: 10, weight: .bold)).lineLimit(1)
                        Text(remote.componentNames[component] ?? "Empty")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2).frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                        Menu("Install / Swap") {
                            ForEach(compatible) { item in
                                Button(item.name) { remote.swapModule(component: component, moduleID: item.id) }
                            }
                        }
                        .font(.system(size: 10, weight: .semibold)).tint(Theme.accent)
                        .disabled(compatible.isEmpty)
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
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
            Text("SLOT SIGNAL CHAIN").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Theme.muted)
            HStack(alignment: .top, spacing: 8) {
                ForEach(["midi_fx1", "synth", "fx1", "fx2"], id: \.self) { component in
                    let title = component == "synth" ? "Instrument" : (component == "midi_fx1" ? "MIDI" : "Audio FX \(component == "fx1" ? "1" : "2")")
                    let selected = selectedComponent == component
                    let loaded = remote.componentNames[component] != nil
                    let bypassed = remote.isComponentBypassed(component)
                    VStack(alignment: .leading, spacing: 7) {
                        Button { selectedComponent = component } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                                Text(remote.componentNames[component] ?? "Empty")
                                    .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2).frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.white)
                        }.buttonStyle(.plain)
                        HStack(spacing: 4) {
                            Circle().fill(loaded && !bypassed ? Theme.success : Theme.warning).frame(width: 6, height: 6)
                            Text(!loaded ? "EMPTY" : (bypassed ? "OFF" : "ON"))
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(!loaded || bypassed ? Theme.warning : Theme.success)
                        }
                        Button(bypassed ? "Enable" : "Bypass") {
                            remote.setComponentBypassed(component, bypassed: !bypassed)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.bordered).tint(bypassed ? Theme.success : Theme.accent)
                        .disabled(!remote.isConnected || !loaded)
                        Button("Clear") { remote.clearSlotModule(component: component) }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.bordered).tint(Theme.warning)
                            .disabled(!remote.isConnected || !loaded)
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1) }
                }
            }
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
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
