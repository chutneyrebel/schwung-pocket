import SwiftUI
import Foundation
import UIKit

private enum PocketTab: String, CaseIterable, Hashable, Identifiable {
    case home, modules, mirror, manager, files, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .modules: return "Modules"
        case .mirror: return "Mirror"
        case .manager: return "Manager"
        case .files: return "Files"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "waveform.path"
        case .modules: return "square.grid.2x2.fill"
        case .mirror: return "rectangle.inset.filled"
        case .manager: return "slider.horizontal.3"
        case .files: return "folder"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @ObservedObject var device: MoveConnectionStore
    @State private var selectedTab: PocketTab = .home
    @AppStorage("SchwungPocket.BottomTabOrder.v1") private var storedTabOrder = "home,modules,mirror,manager,settings"

    private var orderedTabs: [PocketTab] {
        let saved = storedTabOrder.split(separator: ",").compactMap { PocketTab(rawValue: String($0)) }
        // Migrate v0.4.2's saved order, which included Vault and had no Modules tab.
        if storedTabOrder.contains("vault") || !saved.contains(.modules) {
            return [.home, .modules, .mirror, .manager, .settings]
        }
        return saved + PocketTab.allCases.filter { !saved.contains($0) }
    }

    @ViewBuilder
    private func content(for tab: PocketTab) -> some View {
        switch tab {
        case .home:
            HomeScreen(device: device, openModules: { selectedTab = .modules }, openManager: { selectedTab = .manager }, openMirror: { selectedTab = .mirror }, openVault: { selectedTab = .files }, openSettings: { selectedTab = .settings })
        case .modules:
            ModuleHubScreen(device: device, showsCloseButton: false)
        case .manager:
            ManagerScreen(device: device)
        case .files:
            FilesScreen(device: device)
        case .mirror:
            MirrorScreen(device: device)
        case .settings:
            ConnectionSettingsScreen(device: device)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(orderedTabs) { tab in
                content(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(Theme.background.ignoresSafeArea())
    }
}

private enum FavoriteDestination: String, CaseIterable, Identifiable {
    case modules, nativeControls, sampleLab, grooveToolkit, manager, mirror, files, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modules: return "Modules"
        case .nativeControls: return "SchwungTroller"
        case .sampleLab: return "Sample Lab"
        case .grooveToolkit: return "Groove Toolkit"
        case .manager: return "Manager"
        case .mirror: return "Screen mirror"
        case .files: return "Files"
        case .settings: return "Connection settings"
        }
    }

    var subtitle: String {
        switch self {
        case .modules: return "Browse installed companion modules"
        case .nativeControls: return "Live instrument controls"
        case .sampleLab: return "Audition samples on iPhone"
        case .grooveToolkit: return "Build and export MIDI grooves"
        case .manager: return "Schwung Manager pages"
        case .mirror: return "Move display + LEDs"
        case .files: return "Browse files on Move"
        case .settings: return "Device address and status"
        }
    }

    var symbol: String {
        switch self {
        case .modules: return "square.grid.2x2.fill"
        case .nativeControls: return "dial.medium"
        case .sampleLab: return "waveform"
        case .grooveToolkit: return "circle.grid.3x3.fill"
        case .manager: return "slider.horizontal.3"
        case .mirror: return "rectangle.inset.filled"
        case .files: return "folder"
        case .settings: return "network"
        }
    }

    var tint: Color {
        switch self {
        case .modules: return Theme.violet
        case .nativeControls: return Theme.accent
        case .sampleLab: return Theme.blue
        case .grooveToolkit: return Theme.violet
        case .manager: return Theme.violet
        case .mirror: return Theme.blue
        case .files: return Theme.accent
        case .settings: return Theme.warning
        }
    }
}

private struct HomeScreen: View {
    @ObservedObject var device: MoveConnectionStore
    let openModules: () -> Void
    let openManager: () -> Void
    let openMirror: () -> Void
    let openVault: () -> Void
    let openSettings: () -> Void

    @AppStorage("SchwungPocket.FavouriteActions") private var favouriteIDs = "manager,mirror,files"
    @State private var showingFavouriteEditor = false
    @State private var quickModule: PocketStudioModule?

    private var favouriteDestinations: [FavoriteDestination] {
        let selected = favouriteIDs.split(separator: ",").map(String.init)
        return selected.compactMap { id in FavoriteDestination(rawValue: id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    connectionCard
                    favouriteActions
                    moduleHubEntry
                    noteWorkflowCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingFavouriteEditor) {
                FavouriteActionsEditor(favouriteIDs: $favouriteIDs)
                    .preferredColorScheme(.dark)
            }
            .sheet(item: $quickModule) { module in
                NavigationStack {
                    module.destination(device: device)
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SCHWUNG")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(3.6)
                        .foregroundStyle(Theme.accent)
                    Text("Pocket")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.surfaceRaised)
                        .frame(width: 58, height: 58)
                    Image(systemName: "waveform.path")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Text("Your Move, one tap away.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 2)
    }

    private var connectionCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accent.opacity(0.13))
                            .frame(width: 42, height: 42)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ABLETON MOVE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(Theme.muted)
                        Text(device.status.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 4)
                    statusDot
                }
                Text(device.status.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let lastCheckedAt = device.lastCheckedAt {
                    Text("Last checked \(lastCheckedAt, style: .relative)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted.opacity(0.85))
                } else {
                    Text("Auto-checks when the app is open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted.opacity(0.85))
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await device.checkConnection() }
                    } label: {
                        HStack(spacing: 8) {
                            if device.status == .checking {
                                ProgressView().tint(Theme.background)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(device.status == .checking ? "Checking" : "Check now")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .disabled(device.status == .checking)

                    Button(action: openSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 44)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .accessibilityLabel("Connection settings")
                }
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch device.status {
        case .connected:
            Circle().fill(Theme.success).frame(width: 9, height: 9)
        case .checking:
            ProgressView().tint(Theme.accent).scaleEffect(0.85)
        case .failed:
            Circle().fill(Color.red.opacity(0.9)).frame(width: 9, height: 9)
        case .idle:
            Circle().fill(Theme.muted.opacity(0.65)).frame(width: 9, height: 9)
        }
    }

    private var favouriteActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUICK CONTROL")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.8)
                        .foregroundStyle(Theme.muted)
                    Text("Your favourites")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button("EDIT") { showingFavouriteEditor = true }
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(favouriteDestinations) { destination in
                    ActionTile(
                        title: destination.title,
                        subtitle: destination.subtitle,
                        symbol: destination.symbol,
                        tint: destination.tint,
                        action: { open(destination) }
                    )
                }
            }

            if favouriteDestinations.isEmpty {
                Text("No shortcuts selected. Tap Edit to add your favourites.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func open(_ destination: FavoriteDestination) {
        switch destination {
        case .modules: openModules()
        case .nativeControls: quickModule = .nativeControls
        case .sampleLab: quickModule = .sampleLab
        case .grooveToolkit: quickModule = .grooveToolkit
        case .manager: openManager()
        case .mirror: openMirror()
        case .files: openVault()
        case .settings: openSettings()
        }
    }

    private var moduleHubEntry: some View {
        Button { openModules() } label: {
            PocketCard {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                        .frame(width: 42, height: 42)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Installed Modules")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Scan the Schwung Manager for discoverable tools")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var noteWorkflowCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundStyle(Theme.accent)
                    Text("MOVE ↔ NOTE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(.white)
                }
                Text("Sketch on your phone. Shape it on Move.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Use Ableton Cloud to move compatible Sets between Note and Move. Ableton Link syncs timing, not clips or projects. Schwung-only instruments will not appear as instruments in Note, so capture their sound as audio when you need a portable version.")
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Theme.muted)
            Text("Local-network companion. Schwung Manager itself has no password, so use it only on a trusted network.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 3)
    }
}

private struct FavouriteActionsEditor: View {
    @Binding var favouriteIDs: String
    @Environment(\.dismiss) private var dismiss
    @State private var orderedDestinations: [FavoriteDestination]

    init(favouriteIDs: Binding<String>) {
        self._favouriteIDs = favouriteIDs
        let saved = favouriteIDs.wrappedValue.split(separator: ",").compactMap { FavoriteDestination(rawValue: String($0)) }
        let remainder = FavoriteDestination.allCases.filter { !saved.contains($0) }
        self._orderedDestinations = State(initialValue: saved + remainder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orderedDestinations) { destination in
                        Button {
                            if favouriteIDs.split(separator: ",").map(String.init).contains(destination.rawValue) {
                                favouriteIDs = favouriteIDs.split(separator: ",").map(String.init).filter { $0 != destination.rawValue }.joined(separator: ",")
                            } else {
                                var ids = favouriteIDs.split(separator: ",").map(String.init)
                                ids.append(destination.rawValue)
                                favouriteIDs = ids.joined(separator: ",")
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: destination.symbol)
                                    .foregroundStyle(destination.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(destination.title).foregroundStyle(.primary)
                                    Text(destination.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if favouriteIDs.split(separator: ",").map(String.init).contains(destination.rawValue) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { source, destination in orderedDestinations.move(fromOffsets: source, toOffset: destination) }
                } header: {
                    Text("Choose shortcuts and drag to reorder")
                }
                Section {
                    Text("Tap to enable or disable a shortcut. Tap Edit to change the order. Your chosen order is used on the Home screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Quick Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let enabled = Set(favouriteIDs.split(separator: ",").map(String.init))
                        favouriteIDs = orderedDestinations.filter { enabled.contains($0.rawValue) }.map(\.rawValue).joined(separator: ",")
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack {
                    Text("OPEN")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PocketModuleShortcut: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var route: String
    var symbol: String
    var notes: String
}

private struct SchwungCatalogResponse: Decodable {
    let modules: [SchwungCatalogModule]
}

private struct SchwungCatalogModule: Decodable, Identifiable {
    let id: String
    let name: String
    let component_type: String?
    let subcategory: String?
}

private struct ModuleHubScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var device: MoveConnectionStore
    var showsCloseButton: Bool = true
    @AppStorage("SchwungPocket.ModuleShortcuts.v1") private var storedShortcuts = ""
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var selectedShortcut: PocketModuleShortcut?
    @State private var scanMessage = "Not scanned yet"
    @State private var discoveredRoutes: [PocketModuleShortcut] = []
    @State private var isScanning = false
    @State private var showingDiscovery = false
    @State private var catalogEntries: [SchwungCatalogModule] = []
    // Categorisation is cached after a scan. Doing catalog matching inside a computed SwiftUI
    // view caused the entire catalog to be re-scanned repeatedly during expansion/layout.
    @State private var cachedDiscoveredGroups: [CategorizedModuleRoutes] = []

    private enum ModuleCategory: String, CaseIterable, Identifiable {
        case soundGenerators = "Sound Generators"
        case audioFX = "Audio FX"
        case midiFX = "MIDI FX"
        case overtake = "Overtake"
        case tools = "Tools"
        case utilities = "Utilities"
        case other = "Other / Unclassified"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .soundGenerators: return "waveform"
            case .audioFX: return "slider.horizontal.3"
            case .midiFX: return "pianokeys"
            case .overtake: return "rectangle.expand.vertical"
            case .tools: return "wrench.and.screwdriver"
            case .utilities: return "gearshape.2"
            case .other: return "square.grid.2x2"
            }
        }
    }

    // Names and IDs below mirror the component_type taxonomy in Schwung's public catalog.
    // The discovery scan matches discovered URL/name tokens against these known catalog entries.
    private static let catalogCategories: [ModuleCategory: Set<String>] = [
        .soundGenerators: [
            "omega", "dexed", "sf2", "sf2 synth", "sfz", "multisampler", "minijv", "mini-jv", "obxd", "ob-xd", "braids", "hera", "surge", "surge xt", "moog", "raffosynth", "webstream", "radiogarden", "radio garden", "airplay", "streamrtsp", "stream rtsp", "chiptune", "osirus", "plaits", "nusaw", "nu saw", "acid", "vital", "poly", "synth", "sound generator", "granny", "mrhyde", "mr hyde", "weird dreams", "essaim", "forge", "movy", "mrsample", "mr sample", "chordism", "helm", "aphex", "9w9", "6w6", "tablor"
        ],
        .audioFX: [
            "cloudseed", "ottx", "midiverb", "tapescam", "psxverb", "psx verb", "mverb", "tapedelay", "tape delay", "tape-echo2", "tape echo 2", "ruminant", "munchi-delay", "munchi delay", "junologue-chorus", "junologue chorus", "nam", "ducker", "pushnpull", "push n pull", "airwindows", "clap", "gate", "keydetect", "key detect", "vocoder", "usefulity", "reverb", "delay", "chorus", "compressor", "audio fx", "audio_fx", "effect", "effects", "dragonfly hall", "punch in fx", "punchfx", "structor", "dissolver", "spectra", "chowtape", "ambiotica", "rrverb10", "rrverb 10", "capicola", "4k eq", "groovebank"
        ],
        .midiFX: [
            "velocity_scale", "velocity scale", "superarp", "super arp", "eucalypso", "fork", "arpeggiator", "midi fx", "midi_fx"
        ],
        .overtake: [
            "m8", "m8 lpp emulator", "sidcontrol", "sid control", "control", "custom midi control", "overtake", "controller", "performance fx", "sampler looper", "alpha juno 2 ctrl", "juno control"
        ],
        .tools: [
            "samplerobot", "autosample", "waveform-editor", "wave edit", "stretch", "time stretch", "stems", "sampling", "editing", "tool", "tools", "tuner", "analysis", "assistant", "performance", "guitar tuner", "tuner", "chorddex", "chord dex", "dronage move", "chord finder", "arranger", "davebox", "davebox sa"
        ],
        .utilities: [
            "utility", "utilities", "settings", "system", "backup", "file manager", "update", "routing utility"
        ],
        .other: []
    ]

    private func normalizedCatalogToken(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: ".html", with: "")
            .replacingOccurrences(of: ".htm", with: "")
            .replacingOccurrences(of: ".php", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "\\", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func catalogCategory(for componentType: String?) -> ModuleCategory? {
        switch componentType?.lowercased() {
        case "sound_generator": return .soundGenerators
        case "audio_fx": return .audioFX
        case "midi_fx": return .midiFX
        case "overtake": return .overtake
        case "tool": return .tools
        case "utility", "utilities": return .utilities
        default: return nil
        }
    }

    private func containsCatalogToken(_ token: String, in value: String) -> Bool {
        let normalizedToken = normalizedCatalogToken(token)
        let normalizedValue = normalizedCatalogToken(value)
        guard !normalizedToken.isEmpty, !normalizedValue.isEmpty else { return false }
        let paddedValue = " " + normalizedValue + " "
        let paddedToken = " " + normalizedToken + " "
        return paddedValue.contains(paddedToken) || normalizedValue.replacingOccurrences(of: " ", with: "") == normalizedToken.replacingOccurrences(of: " ", with: "")
    }

    private func category(for route: PocketModuleShortcut) -> ModuleCategory {
        let searchableFields = [route.name, route.route]
        // First use the live catalog's full module list and component_type. This keeps categories
        // aligned with schwung.dev instead of relying only on guesses from URL labels.
        let matches = catalogEntries.filter { entry in
            searchableFields.contains { field in
                containsCatalogToken(entry.id, in: field) || containsCatalogToken(entry.name, in: field)
            }
        }.sorted { max($0.id.count, $0.name.count) > max($1.id.count, $1.name.count) }
        if let match = matches.first, let category = catalogCategory(for: match.component_type) {
            return category
        }

        // Offline fallback for commonly used catalog entries if the website cannot be reached.
        let ordered: [ModuleCategory] = [.soundGenerators, .audioFX, .midiFX, .overtake, .tools, .utilities]
        for category in ordered {
            for catalogToken in Self.catalogCategories[category, default: []].sorted(by: { $0.count > $1.count }) {
                if searchableFields.contains(where: { containsCatalogToken(catalogToken, in: $0) }) {
                    return category
                }
            }
        }
        return .other
    }

    private struct CategorizedModuleRoutes: Identifiable {
        let category: ModuleCategory
        let routes: [PocketModuleShortcut]
        var id: String { category.id }
    }

    private var groupedDiscoveredRoutes: [CategorizedModuleRoutes] {
        cachedDiscoveredGroups
    }

    @MainActor
    private func rebuildDiscoveredGroups() {
        // Calculate each route's category exactly once per scan, never during body evaluation.
        var grouped: [ModuleCategory: [PocketModuleShortcut]] = [:]
        for route in discoveredRoutes {
            grouped[category(for: route), default: []].append(route)
        }
        cachedDiscoveredGroups = ModuleCategory.allCases.compactMap { category in
            guard let routes = grouped[category], !routes.isEmpty else { return nil }
            return CategorizedModuleRoutes(category: category, routes: routes)
        }
    }

    private var shortcuts: [PocketModuleShortcut] {
        guard !storedShortcuts.isEmpty,
              let data = storedShortcuts.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PocketModuleShortcut].self, from: data) else {
            return [
                PocketModuleShortcut(name: "Schwung Manager", route: "/", symbol: "slider.horizontal.3", notes: "Open the main Manager"),
                PocketModuleShortcut(name: "Move Mirror", route: "/mirror", symbol: "rectangle.inset.filled", notes: "Display mirror, if enabled")
            ]
        }
        return decoded
    }

    private var filteredShortcuts: [PocketModuleShortcut] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return shortcuts }
        return shortcuts.filter { "\($0.name) \($0.route) \($0.notes)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("SCHWUNG TOOLS")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(2.0)
                                .foregroundStyle(Theme.accent)
                            Text("Module Hub")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Your shortcuts to the parts of Schwung you use most.")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        if showsCloseButton {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(Theme.surfaceRaised, in: Circle())
                            }
                            .accessibilityLabel("Close Module Hub")
                        }
                    }

                    PocketCard {
                        HStack(spacing: 12) {
                            Image(systemName: "network")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(device.status == .connected ? Theme.success : Theme.warning)
                                .frame(width: 42, height: 42)
                                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.status.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(device.addressText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                Task { await device.checkConnection() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(10)
                                    .background(Theme.surfaceRaised, in: Circle())
                            }
                            .accessibilityLabel("Check Move connection")
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(PocketStudioModule.allCases) { module in
                            StudioModuleCard(module: module, device: device)
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.muted)
                        TextField("Search your shortcuts", text: $searchText)
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(13)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))


                    HStack {
                        Text("YOUR MODULE SHORTCUTS")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.6)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Button { showingAdd = true } label: {
                            Label("Add", systemImage: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    if filteredShortcuts.isEmpty {
                        PocketCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Theme.violet)
                                Text(shortcuts.isEmpty ? "Build your own launchpad" : "No matching shortcuts")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(shortcuts.isEmpty
                                     ? "Add a shortcut using a page path or full URL that you know works in Schwung Manager. For example, add /mirror for the display mirror."
                                     : "Try a different search, or clear the search field.")
                                    .font(.system(size: 13))
                                    .lineSpacing(4)
                                    .foregroundStyle(Theme.muted)
                                if shortcuts.isEmpty {
                                    Button("Add your first shortcut") { showingAdd = true }
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Theme.background)
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 11)
                                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(filteredShortcuts) { shortcut in
                                Button { selectedShortcut = shortcut } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Image(systemName: shortcut.symbol.isEmpty ? "waveform" : shortcut.symbol)
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(Theme.accent)
                                            .frame(width: 44, height: 44)
                                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                        Text(shortcut.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(shortcut.route)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Theme.muted)
                                            .lineLimit(1)
                                        if !shortcut.notes.isEmpty {
                                            Text(shortcut.notes)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.muted)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                        HStack {
                                            Text("OPEN")
                                                .font(.system(size: 10, weight: .heavy))
                                                .tracking(1.2)
                                            Spacer()
                                            Image(systemName: "arrow.up.right")
                                        }
                                        .foregroundStyle(Theme.accent)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        removeShortcut(shortcut)
                                    } label: {
                                        Label("Delete shortcut", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Button { withAnimation(.easeInOut(duration: 0.18)) { showingDiscovery.toggle() } } label: {
                                HStack(spacing: 9) {
                                    Label("Module discovery", systemImage: "viewfinder")
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    Spacer()
                                    if !discoveredRoutes.isEmpty {
                                        Text("\(discoveredRoutes.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                                    }
                                    Image(systemName: showingDiscovery ? "chevron.up" : "chevron.down").foregroundStyle(Theme.muted)
                                }
                            }
                            .buttonStyle(.plain)
                            if showingDiscovery {
                                HStack {
                                    Text(scanMessage).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    Spacer(minLength: 8)
                                    Button(isScanning ? "Scanning…" : "Scan Move") { Task { await scanManagerRoutes() } }
                                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent).disabled(isScanning)
                                }
                                ForEach(groupedDiscoveredRoutes) { group in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Label("\(group.category.rawValue) · \(group.routes.count)", systemImage: group.category.symbol)
                                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                                        ForEach(group.routes) { route in
                                            HStack(spacing: 8) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(route.name).foregroundStyle(.white).font(.system(size: 13, weight: .medium))
                                                    Text(route.route).foregroundStyle(Theme.muted).font(.system(size: 10, design: .monospaced))
                                                }
                                                Spacer()
                                                Button("Add") { if !shortcuts.contains(where: { $0.route == route.route }) { save(shortcuts + [route]) } }
                                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                                Text("Discovered routes are matched against the live Schwung catalog when internet is available, with an offline fallback list. Routes that do not match remain in Other / Unclassified. The scan only sees routes exposed by Manager, not a guaranteed inventory of every installed module.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                            } else {
                                Text(discoveredRoutes.isEmpty ? "Scan the Move to find routes and match them to Schwung catalog categories." : "\(discoveredRoutes.count) routes found. Catalog matches are grouped by module type.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                Button(isScanning ? "Scanning…" : "Scan Move") { Task { await scanManagerRoutes(); showingDiscovery = true } }
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent).disabled(isScanning)
                            }
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("How module shortcuts work", systemImage: "info.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Schwung Manager's module discovery interface is not assumed here. This hub saves the exact URLs or paths you provide and opens them inside the app. Use only routes you have verified on your Move.")
                                .font(.system(size: 12))
                                .lineSpacing(4)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task { await scanManagerRoutes() }
            .sheet(isPresented: $showingAdd) {
                AddModuleShortcutSheet { shortcut in
                    var updated = shortcuts
                    updated.append(shortcut)
                    save(updated)
                }
                .preferredColorScheme(.dark)
            }
            .sheet(item: $selectedShortcut) { shortcut in
                NavigationStack {
                    Group {
                        if let url = resolvedURL(for: shortcut) {
                            ManagerWebView(url: url)
                                .ignoresSafeArea(edges: .bottom)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "link.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Theme.warning)
                                Text("This shortcut URL is invalid")
                                    .foregroundStyle(.white)
                                Text(shortcut.route)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.background)
                        }
                    }
                    .navigationTitle(shortcut.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { selectedShortcut = nil }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private func resolvedURL(for shortcut: PocketModuleShortcut) -> URL? {
        let route = shortcut.route.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !route.isEmpty else { return nil }
        if let absolute = URL(string: route), let scheme = absolute.scheme?.lowercased(), ["http", "https"].contains(scheme), absolute.host != nil {
            return absolute
        }
        guard let base = device.managerURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        // Treat paths as origin-relative. This also makes "/" resolve to the manager root.
        let path = route.hasPrefix("/") ? route : "/" + route
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    @MainActor
    private func scanManagerRoutes() async {
        guard let url = device.managerURL else {
            scanMessage = "Enter a valid Move address in Settings first."
            return
        }
        isScanning = true
        defer { isScanning = false }

        // Refresh the official Schwung catalog in the background. If the iPhone is offline,
        // the bundled alias map remains available as a fallback.
        if let catalogURL = URL(string: "https://raw.githubusercontent.com/charlesvestal/schwung/main/module-catalog.json") {
            do {
                let (catalogData, catalogResponse) = try await URLSession.shared.data(from: catalogURL)
                if (catalogResponse as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                   let decoded = try? JSONDecoder().decode(SchwungCatalogResponse.self, from: catalogData) {
                    catalogEntries = decoded.modules
                }
            } catch {
                // Use the last successful catalog or bundled fallback aliases.
            }
        }

        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                scanMessage = "Manager responded unexpectedly. Check the connection and try again."
                return
            }
            // Manager pages can contain large embedded scripts. Avoid parsing an unexpectedly
            // huge document and cap discovered routes so expanding the section cannot create
            // thousands of eager SwiftUI rows.
            guard data.count <= 4 * 1024 * 1024 else {
                scanMessage = "Manager page is unusually large. Discovery was stopped to keep the app responsive."
                return
            }
            let html = String(decoding: data, as: UTF8.self)
            let pattern = #"(?i)href\s*=\s*[\"']([^\"'#]+)[\"']"#
            let regex = try NSRegularExpression(pattern: pattern)
            let ns = html as NSString
            var seen = Set<String>()
            var found: [PocketModuleShortcut] = []
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                if found.count >= 120 { break }
                guard match.numberOfRanges > 1 else { continue }
                let raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty, !raw.hasPrefix("javascript:"), !raw.hasPrefix("mailto:") else { continue }
                let candidate: URL?
                if raw.hasPrefix("http://") || raw.hasPrefix("https://") { candidate = URL(string: raw) }
                else if raw.hasPrefix("/") { candidate = URL(string: raw, relativeTo: url)?.absoluteURL }
                else { candidate = URL(string: raw, relativeTo: url)?.absoluteURL }
                guard let candidate, candidate.host == url.host, ["http", "https"].contains(candidate.scheme?.lowercased() ?? "") else { continue }
                let route = candidate.path.isEmpty ? "/" : candidate.path
                guard seen.insert(route).inserted else { continue }
                let label = route == "/" ? "Schwung Manager" : route.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "-", with: " ").capitalized ?? route
                found.append(PocketModuleShortcut(name: label, route: route, symbol: "waveform", notes: "Discovered from Manager page"))
            }
            discoveredRoutes = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            rebuildDiscoveredGroups()
            scanMessage = found.isEmpty ? "No module links were exposed in the Manager page source. This does not mean no modules are installed." : "Found \(found.count) discoverable route(s). Review them before adding shortcuts."
        } catch {
            scanMessage = "Scan failed: \(error.localizedDescription)"
        }
    }

    private func save(_ items: [PocketModuleShortcut]) {
        guard let data = try? JSONEncoder().encode(items), let string = String(data: data, encoding: .utf8) else { return }
        storedShortcuts = string
    }

    private func removeShortcut(_ shortcut: PocketModuleShortcut) {
        save(shortcuts.filter { $0.id != shortcut.id })
    }
}

private struct AddModuleShortcutSheet: View {
    let onSave: (PocketModuleShortcut) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var route = "/mirror"
    @State private var symbol = "waveform"
    @State private var notes = ""
    @State private var showValidation = false

    private let symbols = ["waveform", "slider.horizontal.3", "pianokeys", "music.note", "folder", "square.grid.2x2", "sparkles", "metronome", "dot.radiowaves.left.and.right", "gearshape"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Shortcut") {
                    TextField("Name, e.g. My module", text: $name)
                    TextField("Page path or full URL", text: $route)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Short note (optional)", text: $notes, axis: .vertical)
                    Picker("Icon", selection: $symbol) {
                        ForEach(symbols, id: \.self) { item in
                            Label(item.capitalized, systemImage: item).tag(item)
                        }
                    }
                }
                Section {
                    Text("Use a known working path such as /mirror, or paste a full http:// or https:// URL. This does not discover module routes automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if showValidation {
                    Section {
                        Text("Enter a name and a page path or full URL.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanRoute = route.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanName.isEmpty, !cleanRoute.isEmpty else {
                            showValidation = true
                            return
                        }
                        onSave(PocketModuleShortcut(name: cleanName, route: cleanRoute, symbol: symbol, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)))
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ManagerScreen: View {
    @ObservedObject var device: MoveConnectionStore
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let url = device.managerURL {
                    ManagerWebView(url: url)
                        .id(reloadToken)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    InvalidAddressView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Schwung Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reloadToken = UUID() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Reload Manager")
                }
            }
        }
    }
}

private struct FilesScreen: View {
    @ObservedObject var device: MoveConnectionStore

    var body: some View {
        NavigationStack {
            Group {
                if let url = device.filesURL {
                    ManagerWebView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    InvalidAddressView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private enum MirrorDisplayMode: String, CaseIterable, Identifiable {
    case both, top, bottom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: return "Both"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
    var symbol: String {
        switch self {
        case .both: return "rectangle.split.2x1"
        case .top: return "rectangle.tophalf.filled"
        case .bottom: return "rectangle.bottomhalf.filled"
        }
    }
}

private struct MirrorScreen: View {
    @ObservedObject var device: MoveConnectionStore
    @State private var reloadToken = UUID()
    @State private var isFullScreen = false
    @State private var recordTrigger: UUID?
    @State private var fullScreenRecordTrigger: UUID?
    @State private var audioTrigger: UUID?
    @State private var fullScreenAudioTrigger: UUID?
    @State private var showingRecordMessage = false
    @State private var recordMessage = ""
    @State private var isRecording = false
    @AppStorage("SchwungPocket.MirrorZoom.v1") private var mirrorZoom = 1.0
    @AppStorage("SchwungPocket.MirrorDisplayMode.v1") private var savedMirrorDisplayMode = "both"

    private var mirrorDisplayMode: MirrorDisplayMode {
        MirrorDisplayMode(rawValue: savedMirrorDisplayMode) ?? .both
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let url = device.mirrorURL {
                    ManagerWebView(
                        url: url,
                        pageZoom: CGFloat(mirrorZoom),
                        mirrorDisplayMode: mirrorDisplayMode.rawValue,
                        fitMirrorViewport: true,
                        recordTrigger: recordTrigger,
                        audioTrigger: audioTrigger,
                        onAudioControlResult: { result in
                            audioTrigger = nil
                            if result != "enabled" {
                                recordMessage = "The portal audio control was not found. Try tapping Unmute on the web page once, then use this shortcut again."
                                showingRecordMessage = true
                            }
                        },
                        onRecordControlResult: { result in
                            recordTrigger = nil
                            if result == "started" { isRecording = true }
                            else if result == "stopped" { isRecording = false }
                            else {
                                recordMessage = "I couldn't identify the portal's recording control. Open the recording controls on the web page once, then try again."
                                showingRecordMessage = true
                            }
                        }
                    )
                    .id(reloadToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    InvalidAddressView()
                }

                HStack(spacing: 10) {
                    Menu {
                        ForEach(MirrorDisplayMode.allCases) { mode in
                            Button {
                                savedMirrorDisplayMode = mode.rawValue
                            } label: {
                                if mirrorDisplayMode == mode {
                                    Label(mode.title, systemImage: "checkmark")
                                } else {
                                    Text(mode.title)
                                }
                            }
                        }
                    } label: {
                        Label(mirrorDisplayMode.title, systemImage: mirrorDisplayMode.symbol)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .accessibilityLabel("Choose mirrored display layout")

                    Button { mirrorZoom = max(0.75, mirrorZoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Zoom out")
                    Text("\(Int(mirrorZoom * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                    Button { mirrorZoom = min(1.6, mirrorZoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoom in")
                    Button { audioTrigger = UUID() } label: { Image(systemName: "speaker.wave.2.fill") }
                        .accessibilityLabel("Enable mirror audio")
                    Button { recordTrigger = UUID() } label: {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                    }
                    .accessibilityLabel(isRecording ? "Stop mirror portal screen recording" : "Start mirror portal screen recording")
                    Button { reloadToken = UUID(); Task { await device.checkConnection() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh Move mirror")
                    Button { isFullScreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .accessibilityLabel("Open full-screen mirror")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.background.opacity(0.96))


            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Screen Recording", isPresented: $showingRecordMessage) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(recordMessage)
            }
            .fullScreenCover(isPresented: $isFullScreen) {
                if let url = device.mirrorURL {
                    FullscreenMirrorView(device: device, url: url, zoom: $mirrorZoom, reloadToken: UUID(), displayModeSelection: Binding(get: { savedMirrorDisplayMode }, set: { savedMirrorDisplayMode = $0 }), recordTrigger: $fullScreenRecordTrigger, audioTrigger: $fullScreenAudioTrigger, isRecording: $isRecording)
                } else {
                    InvalidAddressView()
                }
            }
            .onAppear { if device.lastCheckedAt == nil { Task { await device.checkConnection() } } }
        }
    }
}

private struct FullscreenMirrorView: View {
    @ObservedObject var device: MoveConnectionStore
    let url: URL
    @Binding var zoom: Double
    @State var reloadToken: UUID
    @Binding var displayModeSelection: String
    @Binding var recordTrigger: UUID?
    @Binding var audioTrigger: UUID?
    @Binding var isRecording: Bool
    @State private var controlsVisible = true
    @State private var showingRecordMessage = false
    @State private var recordMessage = ""
    @AppStorage("SchwungPocket.MirrorKeepAwake.v1") private var keepAwake = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ManagerWebView(
                url: url,
                pageZoom: CGFloat(zoom),
                mirrorDisplayMode: displayModeSelection,
                fitMirrorViewport: true,
                recordTrigger: recordTrigger,
                audioTrigger: audioTrigger,
                onAudioControlResult: { result in
                    audioTrigger = nil
                    if result != "enabled" {
                        recordMessage = "The portal audio control was not found. Try tapping Unmute on the web page once, then use this shortcut again."
                        showingRecordMessage = true
                    }
                },
                onRecordControlResult: { result in
                    recordTrigger = nil
                    if result == "started" { isRecording = true }
                    else if result == "stopped" { isRecording = false }
                    else {
                        recordMessage = "I couldn't identify the portal's recording control. Open the recording controls on the web page once, then try again."
                        showingRecordMessage = true
                    }
                }
            )
                .id(reloadToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()

            if controlsVisible {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                                .frame(width: 38, height: 38).background(.black.opacity(0.72), in: Circle())
                        }
                        .accessibilityLabel("Exit full-screen mirror")
                        Spacer()
                        Menu {
                            ForEach(MirrorDisplayMode.allCases) { mode in
                                Button {
                                    displayModeSelection = mode.rawValue
                                } label: {
                                    if displayModeSelection == mode.rawValue { Label(mode.title, systemImage: "checkmark") }
                                    else { Text(mode.title) }
                                }
                            }
                        } label: {
                            Text("\(displayModeSelection.capitalized) · \(Int(zoom * 100))%")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(.black.opacity(0.72), in: Capsule())
                        }
                        Button { audioTrigger = UUID() } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 14, weight: .bold))
                                .frame(width: 38, height: 38).background(.black.opacity(0.72), in: Circle())
                        }
                        .accessibilityLabel("Enable mirror audio")
                        Button { recordTrigger = UUID() } label: {
                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle").font(.system(size: 14, weight: .bold))
                                .frame(width: 38, height: 38).background(.black.opacity(0.72), in: Circle())
                        }
                        .accessibilityLabel(isRecording ? "Stop mirror portal screen recording" : "Start mirror portal screen recording")
                        Button { reloadToken = UUID(); Task { await device.checkConnection() } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .bold))
                                .frame(width: 38, height: 38).background(.black.opacity(0.72), in: Circle())
                        }
                        .accessibilityLabel("Refresh full-screen mirror")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.top, 10)
                    Spacer()
                    HStack(spacing: 12) {
                        HStack(spacing: 5) {
                            Circle().fill(device.status == .connected ? Theme.success : (device.status == .checking ? Theme.accent : Color.red)).frame(width: 7, height: 7)
                            Text(device.status == .connected ? "Move reachable" : device.status == .checking ? "Checking Move" : "Move offline")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        Button { Task { await device.checkConnection() } } label: { Image(systemName: "antenna.radiowaves.left.and.right") }
                            .accessibilityLabel("Check Move connection")
                        Divider().frame(height: 22).overlay(.white.opacity(0.35))
                        Button { zoom = max(0.75, zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                            .accessibilityLabel("Zoom out")
                        Button { zoom = min(1.6, zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                            .accessibilityLabel("Zoom in")
                        Divider().frame(height: 22).overlay(.white.opacity(0.35))
                        Button { keepAwake.toggle(); UIApplication.shared.isIdleTimerDisabled = keepAwake } label: {
                            Label(keepAwake ? "Keep Awake" : "Allow Sleep", systemImage: keepAwake ? "sun.max.fill" : "moon.zzz")
                        }
                        Button { controlsVisible = false } label: { Image(systemName: "eye.slash") }
                            .accessibilityLabel("Hide mirror controls")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(.bottom, 18)
                }
                .transition(.opacity)
            } else {
                VStack {
                    HStack {
                        Spacer()
                        Button { withAnimation(.easeInOut(duration: 0.15)) { controlsVisible = true } } label: {
                            Image(systemName: "eye").font(.system(size: 13, weight: .bold))
                                .frame(width: 36, height: 36).background(.black.opacity(0.72), in: Circle())
                        }
                        .accessibilityLabel("Show mirror controls")
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .alert("Screen Recording", isPresented: $showingRecordMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(recordMessage)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onChange(of: keepAwake) { newValue in UIApplication.shared.isIdleTimerDisabled = newValue }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

}

private struct ConnectionSettingsScreen: View {
    @ObservedObject var device: MoveConnectionStore
    @FocusState private var addressFocused: Bool
    @AppStorage("SchwungPocket.SavedMoves.v1") private var savedMovesJSON = ""
    @AppStorage("SchwungPocket.SelectedMoveID.v1") private var selectedMoveID = ""
    @AppStorage("SchwungPocket.DefaultMoveID.v1") private var defaultMoveID = ""
    @AppStorage("SchwungPocket.BottomTabOrder.v1") private var storedTabOrder = "home,modules,mirror,manager,settings"
    @State private var moveDisplayName = "My Move"
    @State private var moveProfileMessage = "Save this Move to keep it in your device list."

    private var savedMoves: [SavedMoveProfile] {
        guard let data = savedMovesJSON.data(using: .utf8), let decoded = try? JSONDecoder().decode([SavedMoveProfile].self, from: data) else { return [] }
        return decoded
    }

    private var orderedTabNames: [PocketTab] {
        let saved = storedTabOrder.split(separator: ",").compactMap { PocketTab(rawValue: String($0)) }
        if storedTabOrder.contains("vault") || !saved.contains(.modules) {
            return [.home, .modules, .mirror, .manager, .settings]
        }
        return saved + PocketTab.allCases.filter { !saved.contains($0) }
    }

    private var connectionStatusSymbol: String {
        switch device.status {
        case .idle: return "circle.dashed"
        case .checking: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var connectionStatusColor: Color {
        switch device.status {
        case .idle: return Theme.muted
        case .checking: return Theme.accent
        case .connected: return Theme.success
        case .failed: return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    PocketCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MOVE ADDRESS")
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(1.6)
                                .foregroundStyle(Theme.muted)
                            TextField("move.local:7700", text: $device.addressText)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .submitLabel(.done)
                                .focused($addressFocused)
                                .padding(13)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text("Default: move.local:7700. Replace it with your Move's local IP address and port 7700 if the .local name does not resolve.")
                                .font(.system(size: 12))
                                .lineSpacing(3)
                                .foregroundStyle(Theme.muted)
                            HStack(spacing: 10) {
                                Button {
                                    addressFocused = false
                                    Task { await device.checkConnection() }
                                } label: {
                                    Text("Test connection")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Theme.background)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }
                                .disabled(device.status == .checking)
                                Button("Reset") { device.resetAddress() }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: connectionStatusSymbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(connectionStatusColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.status.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(device.status.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let checked = device.lastCheckedAt {
                                        Text("Last checked: " + checked.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Move profiles", systemImage: "externaldrive.connected.to.line.below")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            Text("Save multiple Moves on the same network and give each a name for identification in this app only.")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            TextField("Move name, e.g. Studio Move", text: $moveDisplayName)
                                .textInputAutocapitalization(.words)
                                .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                            if !savedMoves.isEmpty {
                                ForEach(savedMoves) { profile in
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(profile.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                            Text(profile.address).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                                            if profile.id == defaultMoveID { Text("DEFAULT MOVE").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.accent) }
                                        }
                                        Spacer()
                                        if profile.id == selectedMoveID {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                        } else {
                                            Button("Select") {
                                                selectedMoveID = profile.id
                                                device.addressText = profile.address
                                                moveDisplayName = profile.name
                                                moveProfileMessage = "Selected \(profile.name)."
                                                Task { await device.checkConnection() }
                                            }.font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                                        }
                                        if profile.id != defaultMoveID {
                                            Button { defaultMoveID = profile.id; moveProfileMessage = "\(profile.name) is now the default Move." } label: {
                                                Image(systemName: "star").foregroundStyle(Theme.warning)
                                            }.accessibilityLabel("Set \(profile.name) as default Move")
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            HStack(spacing: 10) {
                                Button("Save / Update Move") { saveCurrentMove() }
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.background)
                                    .padding(11).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                                Button("Use default") {
                                    if let profile = savedMoves.first(where: { $0.id == defaultMoveID }) {
                                        selectedMoveID = profile.id
                                        device.addressText = profile.address
                                        moveDisplayName = profile.name
                                        moveProfileMessage = "Switched to default Move: \(profile.name)."
                                        Task { await device.checkConnection() }
                                    } else { moveProfileMessage = "Save a Move and set it as default first." }
                                }
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            }
                            Text(moveProfileMessage).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Files on Move", systemImage: "folder")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            Text("Browse and manage files stored on your Ableton Move through Schwung Manager.")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            NavigationLink {
                                FilesScreen(device: device)
                            } label: {
                                Label("Open Files", systemImage: "folder")
                                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.background)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Bottom navigation order", systemImage: "arrow.left.arrow.right")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            Text("Move sections up or down. Vault is available inside Settings, not in the bottom navigation.")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            ForEach(Array(orderedTabNames.enumerated()), id: \.element.id) { item in
                                let index = item.offset
                                let tab = item.element
                                HStack {
                                    Image(systemName: tab.symbol).frame(width: 24).foregroundStyle(Theme.accent)
                                    Text(tab.title).foregroundStyle(.white)
                                    Spacer()
                                    Button { moveTab(from: index, by: -1) } label: { Image(systemName: "chevron.up") }
                                        .disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                                    Button { moveTab(from: index, by: 1) } label: { Image(systemName: "chevron.down") }
                                        .disabled(index == orderedTabNames.count - 1).opacity(index == orderedTabNames.count - 1 ? 0.3 : 1)
                                }
                                .font(.system(size: 13, weight: .medium))
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Connection checklist", systemImage: "checklist")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            checklistRow("Move is powered on and Schwung has finished loading.", checked: device.status == .connected)
                            checklistRow("iPhone can reach the Move over the current Wi-Fi network.", checked: device.status == .connected)
                            checklistRow("The configured address uses port 7700.", checked: device.status == .connected && (device.managerURL?.port == 7700))
                            checklistRow("Connection test passed, so local network isolation is not blocking this route.", checked: device.status == .connected)
                            Text("These checks update automatically when the app tests the connection. A successful request cannot identify the Wi-Fi network type itself; it only confirms the Manager is reachable.")
                                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Automatic reconnection", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            Text("While Schwung Pocket is open, it checks the selected Move periodically and retries when the app returns to the foreground. iOS suspends most app activity when the app is in the background.")
                                .font(.system(size: 13)).lineSpacing(4).foregroundStyle(Theme.muted)
                        }
                    }

                    PocketCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Privacy & network safety", systemImage: "lock.shield")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Schwung Manager does not require a password. Keep Move on a trusted local network; do not forward port 7700 to the internet. This app does not add authentication to the Manager.")
                                .font(.system(size: 13))
                                .lineSpacing(4)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(18)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let profile = savedMoves.first(where: { $0.id == selectedMoveID }) {
                    moveDisplayName = profile.name
                }
            }
        }
    }

    private func checklistRow(_ text: String, checked: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(checked ? Theme.success : Theme.muted)
                .padding(.top, 1)
            Text(text).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.muted)
        }
    }

    private func saveCurrentMove() {
        let name = moveDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = device.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !address.isEmpty else {
            moveProfileMessage = "Enter a name and a valid Move address before saving."
            return
        }
        var profiles = savedMoves
        let existingIndex = profiles.firstIndex { $0.id == selectedMoveID || $0.address.caseInsensitiveCompare(address) == .orderedSame }
        let profile: SavedMoveProfile
        if let index = existingIndex {
            profile = SavedMoveProfile(id: profiles[index].id, name: name, address: address)
            profiles[index] = profile
        } else {
            profile = SavedMoveProfile(id: UUID().uuidString, name: name, address: address)
            profiles.append(profile)
        }
        if let data = try? JSONEncoder().encode(profiles), let json = String(data: data, encoding: .utf8) {
            savedMovesJSON = json
            selectedMoveID = profile.id
            if defaultMoveID.isEmpty { defaultMoveID = profile.id }
            moveProfileMessage = "Saved \(name). Set it as default with the star button if needed."
        } else {
            moveProfileMessage = "Could not save this Move profile."
        }
    }

    private func moveTab(from index: Int, by offset: Int) {
        var tabs = orderedTabNames
        let destination = index + offset
        guard tabs.indices.contains(index), tabs.indices.contains(destination) else { return }
        let item = tabs.remove(at: index)
        tabs.insert(item, at: destination)
        storedTabOrder = tabs.map(\.rawValue).joined(separator: ",")
    }
}

private struct InvalidAddressView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.system(size: 36))
                .foregroundStyle(Theme.warning)
            Text("Check the Move address")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Open Settings and enter a valid address such as move.local:7700.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
