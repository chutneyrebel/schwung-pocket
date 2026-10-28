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
                header
                destinationPicker
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
                if case .error(let error) = remote.loadState {
                    infoCard("Could not load controls", detail: error)
                } else if case .unsupported(let reason) = remote.loadState {
                    infoCard("Controls unavailable", detail: reason)
                } else if remote.parameters.isEmpty {
                    infoCard("Waiting for metadata", detail: "Select a destination and wait for Schwung to report its parameter hierarchy. The app does not invent controls for unknown protocol fields.")
                } else {
                    parameterSection
                }
                if isSlotDestination {
                    slotSettings
                    moduleSwapSection
                }
                if !remote.levels.isEmpty {
                    levelPicker
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
                Text("SCHWUNG POCKET / MODULE")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.8).foregroundStyle(Theme.accent)
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
                        Label(destination.title, systemImage: destination.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(remote.destination == destination ? Theme.background : Color.white)
                            .background(remote.destination == destination ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var parameterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(remote.instrumentName.isEmpty ? remote.destination.title : remote.instrumentName)
                        .font(.headline)
                    Text("\(remote.parameters.count) parameters · \(remote.levels.count) levels")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                if remote.isLoadingSlotModules { ProgressView().controlSize(.small) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(remote.parameters) { parameter in
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
                Slider(value: Binding(
                    get: { remote.currentDouble(for: parameter) },
                    set: { remote.setNumeric($0, for: parameter) }
                ), in: parameter.minimum...max(parameter.maximum, parameter.minimum))
                .tint(Theme.accent)
                HStack {
                    Text(parameter.format(parameter.minimum))
                    Spacer()
                    Text(parameter.format(parameter.maximum))
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
            case .choice:
                Picker(parameter.displayName, selection: Binding(
                    get: { remote.currentChoiceIndex(for: parameter) },
                    set: { remote.setChoice($0, for: parameter) }
                )) {
                    ForEach(Array(parameter.options.enumerated()), id: \.offset) { index, option in
                        Text(option).tag(index)
                    }
                }
                .labelsHidden().pickerStyle(.menu).tint(Theme.accent)
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
                    Text("Module discovery from the Schwung Manager API")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Refresh") { remote.loadSlotModules(address: device.baseAddress) }
                    .buttonStyle(.bordered).tint(Theme.accent)
            }
            if remote.availableSlotModules.isEmpty {
                Text("No compatible modules discovered yet.")
                    .font(.callout).foregroundStyle(Theme.muted)
            } else {
                ForEach(["synth", "midi_fx1", "fx1", "fx2"], id: \.self) { component in
                    let compatible = remote.availableSlotModules.filter { module in
                        let expected = component == "synth" ? "sound_generator" : (component.hasPrefix("midi_fx") ? "midi_fx" : "audio_fx")
                        return module.componentType == expected && !module.deviceOnly
                    }
                    if !compatible.isEmpty {
                        HStack {
                            Text(component == "synth" ? "Instrument" : component.replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(.callout.weight(.medium))
                            Spacer()
                            Menu("Swap…") {
                                ForEach(compatible) { module in
                                    Button(module.name) { remote.swapModule(component: component, moduleID: module.id) }
                                }
                            }.tint(Theme.accent)
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
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
