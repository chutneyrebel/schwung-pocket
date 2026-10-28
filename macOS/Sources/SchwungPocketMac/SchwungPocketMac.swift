import AppKit
import SwiftUI
import WebKit

@main
struct SchwungPocketMac: App {
    @StateObject private var device = MoveConnection()
    var body: some Scene {
        WindowGroup {
            PocketWindow(device: device)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct PocketWindow: View {
    @ObservedObject var device: MoveConnection
    @State private var selection: PocketSection = .home

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Color.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCHWUNG").font(.system(size: 13, weight: .black, design: .rounded)).tracking(1.8)
                        Text("POCKET · MAC").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 12)

                ForEach(PocketSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == section ? Color.mint : Color.primary.opacity(0.78))
                    .padding(.horizontal, 10)
                    .background(selection == section ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(device.isReachable ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(device.isReachable ? "Move reachable" : "Move not verified")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .padding(10)
            .frame(minWidth: 205)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selection.title).font(.system(size: 23, weight: .bold, design: .rounded))
                        Text(selection.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await device.check() }
                    } label: {
                        Label("Check Move", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(device.isChecking)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                Divider()
                Group {
                    switch selection {
                    case .home: HomeScreen(device: device, open: { selection = $0 })
                    case .mirror: DeviceWebScreen(url: device.endpoint("/remote-ui"), title: "Move Mirror")
                    case .manager: DeviceWebScreen(url: device.endpoint("/"), title: "Schwung Manager")
                    case .files: DeviceWebScreen(url: device.endpoint("/files"), title: "Move Files")
                    case .studio: StudioScreen(device: device)
                    case .settings: SettingsScreen(device: device)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .task { await device.check() }
    }
}

enum PocketSection: String, CaseIterable, Identifiable {
    case home, mirror, manager, studio, files, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Overview"
        case .mirror: "Move Mirror"
        case .manager: "Schwung Manager"
        case .studio: "Studio"
        case .files: "Files"
        case .settings: "Connection"
        }
    }
    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .mirror: "display"
        case .manager: "slider.horizontal.3"
        case .studio: "dial.low"
        case .files: "folder"
        case .settings: "network"
        }
    }
    var subtitle: String {
        switch self {
        case .home: "Your Move connection at a glance"
        case .mirror: "The device's remote interface"
        case .manager: "Native window into Schwung Manager"
        case .studio: "A home for verified remote controls"
        case .files: "Files exposed by Schwung"
        case .settings: "Device address and connectivity"
        }
    }
}

struct HomeScreen: View {
    @ObservedObject var device: MoveConnection
    var open: (PocketSection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your studio, one window wider.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Schwung Pocket for macOS is a dedicated desktop companion for Ableton Move. Start with the live device pages, then grow into verified native controls.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 650, alignment: .leading)
                    HStack(spacing: 8) {
                        Circle().fill(device.isReachable ? Color.green : Color.orange).frame(width: 9, height: 9)
                        Text(device.status)
                            .font(.callout.weight(.medium))
                        if device.isChecking { ProgressView().controlSize(.small) }
                    }
                    .padding(.top, 5)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color.mint.opacity(0.15), Color.blue.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    HomeTile(title: "Move Mirror", detail: "Open the Move remote interface", symbol: "display", action: { open(.mirror) })
                    HomeTile(title: "Schwung Manager", detail: "Modules and device management", symbol: "slider.horizontal.3", action: { open(.manager) })
                    HomeTile(title: "Studio Controls", detail: "Verified native control workbench", symbol: "dial.low", action: { open(.studio) })
                    HomeTile(title: "Files", detail: "Browse the device file interface", symbol: "folder", action: { open(.files) })
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection").font(.headline)
                    HStack {
                        Text(device.baseAddress).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Configure") { open(.settings) }.buttonStyle(.link)
                    }
                    Text("Both devices must be on the same local network. The app uses HTTP by default because the current Move Manager endpoint is not configured for HTTPS.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
    }
}

struct HomeTile: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Color.mint).frame(width: 42, height: 42).background(Color.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct StudioScreen: View {
    @ObservedObject var device: MoveConnection
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Control workbench", systemImage: "slider.horizontal.3").font(.title2.bold())
                Text("This area is reserved for native controls driven by protocol messages verified against Schwung. The app will not send guessed messages to your instrument.")
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal").foregroundStyle(.mint).font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Foundation in place").font(.headline)
                        Text("Move address handling, endpoint navigation, and connectivity checks are implemented.")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver").foregroundStyle(.orange).font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Protocol validation pending").font(.headline)
                        Text("Master FX, Tool controls, transport, individual FX mute, and reliable DSP path discovery require captured protocol evidence and tests on the real Move.")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Open Schwung Manager") { if let url = device.endpoint("/") { NSWorkspace.shared.open(url) } }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

struct SettingsScreen: View {
    @ObservedObject var device: MoveConnection
    var body: some View {
        Form {
            Section("Ableton Move") {
                TextField("Base address", text: $device.baseAddress)
                    .textFieldStyle(.roundedBorder)
                Text("Examples: move.local:7700 or http://192.168.1.25:7700")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Test connection") { Task { await device.check() } }
                        .buttonStyle(.borderedProminent).tint(.mint)
                        .disabled(device.isChecking)
                    if device.isChecking { ProgressView().controlSize(.small) }
                }
                LabeledContent("Status", value: device.status)
                if let checked = device.lastChecked {
                    LabeledContent("Last checked", value: checked.formatted(date: .abbreviated, time: .standard))
                }
            }
            Section("Known endpoints") {
                LabeledContent("Manager", value: device.endpoint("/")?.absoluteString ?? "Invalid address")
                LabeledContent("Remote UI", value: device.endpoint("/remote-ui")?.absoluteString ?? "Invalid address")
                LabeledContent("Files", value: device.endpoint("/files")?.absoluteString ?? "Invalid address")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(maxWidth: 760, alignment: .topLeading)
    }
}

struct DeviceWebScreen: View {
    let url: URL?
    let title: String
    @State private var loadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "link").foregroundStyle(.mint)
                Text(url?.absoluteString ?? "Invalid device address")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    loadID = UUID()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            Divider()
            if let url {
                DeviceWebView(url: url, reloadID: loadID)
                    .background(Color.black)
            } else {
                VStack(spacing: 10) { Image(systemName: "network.slash").font(.largeTitle); Text("Invalid address").font(.headline); Text("Open Connection to enter the Move address.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct DeviceWebView: NSViewRepresentable {
    let url: URL
    let reloadID: UUID
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url, timeoutInterval: 15))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.lastReloadID != reloadID {
            context.coordinator.lastReloadID = reloadID
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var lastReloadID = UUID()
    }
}

@MainActor
final class MoveConnection: ObservableObject {
    @Published var baseAddress: String {
        didSet { UserDefaults.standard.set(baseAddress, forKey: "SchwungPocketMac.baseAddress") }
    }
    @Published private(set) var status = "Not checked yet"
    @Published private(set) var isReachable = false
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?

    init() {
        baseAddress = UserDefaults.standard.string(forKey: "SchwungPocketMac.baseAddress") ?? "move.local:7700"
    }

    func endpoint(_ path: String) -> URL? {
        let raw = baseAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let input = raw.contains("://") ? raw : "http://\(raw)"
        guard var components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }
        components.scheme = scheme
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    func check() async {
        guard !isChecking else { return }
        guard let url = endpoint("/") else {
            isReachable = false
            status = "Enter a valid address, such as move.local:7700"
            lastChecked = Date()
            return
        }
        isChecking = true
        defer { isChecking = false; lastChecked = Date() }
        do {
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                isReachable = true
                status = "Move responded (HTTP \(http.statusCode))"
            } else {
                isReachable = false
                status = "Unexpected response from Move"
            }
        } catch {
            isReachable = false
            status = "Connection failed: \(error.localizedDescription)"
        }
    }
}
