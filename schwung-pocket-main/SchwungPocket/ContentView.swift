import SwiftUI

struct ContentView: View {
    @StateObject private var connectionStore = MoveConnectionStore()
    @StateObject private var remoteStore = RemoteControlStore()
    @AppStorage("autoHideToolbar") private var autoHideToolbar = true
    @AppStorage("inactivityTimeout") private var inactivityTimeout = 5.0

    @State private var selectedTab = 0
    @State private var isFullscreenMirror = false
    @State private var isControlsVisible = true
    @State private var inactivityTimer: Timer?

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home / Quick Controls Tab
            HomeView(selectedTab: $selectedTab, remoteStore: remoteStore)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // Mirror Interface Tab
            MirrorView(
                connectionStore: connectionStore,
                isFullscreen: $isFullscreenMirror,
                isControlsVisible: $isControlsVisible,
                resetInactivityTimer: resetInactivityTimer
            )
            .tabItem {
                Label("Mirror", systemImage: "display")
            }
            .tag(1)

            // SchwungTroller Tab
            NativeControlsScreen(remoteStore: remoteStore)
                .tabItem {
                    Label("SchwungTroller", systemImage: "slider.horizontal.3")
                }
                .tag(2)

            // Sample Lab Tab
            SampleLabView()
                .tabItem {
                    Label("Sample Lab", systemImage: "waveform")
                }
                .tag(3)

            // Groove Toolkit Tab
            GrooveToolkitView()
                .tabItem {
                    Label("Groove Toolkit", systemImage: "music.note.list")
                }
                .tag(4)

            // Files Tab (Replaces Vault)
            BackupVaultScreen()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag(5)
        }
        .onAppear { resetInactivityTimer() }
        .onTapGesture { resetInactivityTimer() }
    }

    private func resetInactivityTimer() {
        isControlsVisible = true
        inactivityTimer?.invalidate()
        guard autoHideToolbar else { return }
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { _ in
            withAnimation {
                isControlsVisible = false
            }
        }
    }
}

struct HomeView: View {
    @Binding var selectedTab: Int
    @ObservedObject var remoteStore: RemoteControlStore

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Modules")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        ModuleCard(title: "SchwungTroller", icon: "slider.horizontal.3", color: .blue) {
                            selectedTab = 2
                        }
                        ModuleCard(title: "Sample Lab", icon: "waveform", color: .purple) {
                            selectedTab = 3
                        }
                        ModuleCard(title: "Groove Toolkit", icon: "music.note.list", color: .orange) {
                            selectedTab = 4
                        }
                        ModuleCard(title: "Files", icon: "folder.fill", color: .green) {
                            selectedTab = 5
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Schwung Pocket")
        }
    }
}

struct ModuleCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

struct MirrorView: View {
    @ObservedObject var connectionStore: MoveConnectionStore
    @Binding var isFullscreen: Bool
    @Binding var isControlsVisible: Bool
    var resetInactivityTimer: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            ManagerWebView(url: URL(string: "http://move.local:7700/remote-ui")!)
                .edgesIgnoringSafeArea(isFullscreen ? .all : [])
                .onTapGesture {
                    isFullscreen.toggle()
                    resetInactivityTimer()
                }

            if isControlsVisible && !isFullscreen {
                HStack {
                    Button(action: { connectionStore.toggleAudioMute() }) {
                        Label(connectionStore.isMuted ? "Unmute" : "Mute", systemImage: connectionStore.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button(action: { connectionStore.sendTransportTrigger() }) {
                        Image(systemName: "playpause.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
