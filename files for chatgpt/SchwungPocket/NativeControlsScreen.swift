import SwiftUI
import UIKit

/// SchwungTroller module: destination selector + metadata-driven parameter controls.
struct NativeControlsScreen: View {
    @ObservedObject var device: MoveConnectionStore
    @StateObject private var remote = RemoteControlStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RemoteDiagnostics.defaultsKey) private var diagnosticsEnabled = false
    @State private var copiedReport = false

    var body: some View {
        ModuleScreenShell(
            eyebrow: "SCHWUNG POCKET / MODULE",
            title: "SchwungTroller",
            subtitle: "Live knobs and switches built from the instrument's own metadata."
        ) {
            connectionCard
            destinationCard
            contentSection
        }
        .onAppear {
            if remote.connection == .disconnected { remote.connect(address: device.addressText) }
        }
        .onDisappear { remote.disconnect() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { remote.appDidBecomeActive() }
            else if phase == .background { remote.appDidEnterBackground() }
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
                    if remote.isConnected, case .slot = remote.wireTarget {
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
                    Text("SLOT & INSTRUMENT").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(remote.instrumentName.isEmpty ? " " : remote.instrumentName)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent).lineLimit(1)
                }
                DestinationSelector(selection: remote.destination) { remote.select($0) }
                if remote.levels.count > 1 {
                    Picker("Parameter group", selection: $remote.selectedLevelID) {
                        ForEach(remote.levels) { level in Text(level.name).tag(level.id) }
                    }.pickerStyle(.menu).tint(Theme.accent)
                }
            }
        }
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
            if remote.parameters.isEmpty {
                messageCard(icon: "square.dashed", title: "Nothing to control here",
                            text: "No instrument parameters were reported for \(remote.destination.title).")
            } else {
                parameterBank
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

    private var parameterBank: some View {
        let visible = remote.visibleParameters
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
    let onSelect: (RemoteDestination) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(RemoteDestination.allCases) { destination in
                let isSelected = destination == selection
                Button { onSelect(destination) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: destination.symbol).font(.system(size: 15, weight: .semibold))
                        Text(destination.title)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(isSelected ? Theme.background : Color.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(isSelected ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.06), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
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
