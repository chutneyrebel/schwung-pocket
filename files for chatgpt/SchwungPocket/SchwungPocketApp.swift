import SwiftUI

@main
struct SchwungPocketApp: App {
    @StateObject private var device = MoveConnectionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(device: device)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear {
                    if scenePhase == .active {
                        device.startMonitoring()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        device.startMonitoring()
                    } else {
                        device.stopMonitoring()
                    }
                }
        }
    }
}
