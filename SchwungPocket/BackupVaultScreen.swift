import SwiftUI
import WebKit

struct BackupVaultScreen: View {
    var body: some View {
        NavigationView {
            FilesWebView(url: URL(string: "http://move.local:7700/files")!)
                .navigationTitle("Files")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FilesWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
