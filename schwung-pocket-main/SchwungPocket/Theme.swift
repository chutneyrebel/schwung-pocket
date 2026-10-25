import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.09)
    static let surface = Color(red: 0.095, green: 0.11, blue: 0.145)
    static let surfaceRaised = Color(red: 0.13, green: 0.15, blue: 0.19)
    static let accent = Color(red: 0.75, green: 0.98, blue: 0.31)
    static let violet = Color(red: 0.70, green: 0.59, blue: 1.0)
    static let blue = Color(red: 0.48, green: 0.74, blue: 1.0)
    static let muted = Color(red: 0.63, green: 0.67, blue: 0.74)
    static let success = Color(red: 0.36, green: 0.88, blue: 0.62)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.33)
}

struct PocketCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
            }
    }
}
