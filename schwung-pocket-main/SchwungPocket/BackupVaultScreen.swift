
import SwiftUI
import WebKit

public struct BackupVaultScreen: View {
    @EnvironmentObject var connectionStore: MoveConnectionStore

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                Theme.darkBackground
                    .edgesIgnoringSafeArea(.all)

                ManagerWebView(urlString: connectionStore.filesURL)
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
