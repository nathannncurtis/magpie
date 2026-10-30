import SwiftUI

/// The root screen: the page being read.
struct RootView: View {
    /// The page the browser opens on.
    private static let page = URL(string: "https://example.org") ?? URL(fileURLWithPath: "/")

    var body: some View {
        ReadingScreen(url: Self.page)
    }
}

#Preview {
    RootView()
}
