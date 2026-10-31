import SwiftUI

/// The root screen: the mist with the wordmark centred on it.
struct RootView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Fraunces sizes are scaled by hand, so the body must re-run when the text size changes.
        let _ = dynamicTypeSize
        ZStack {
            MistBackground()
            Text("magpie")
                .font(Typography.wordmark)
                .tracking(Typography.wordmarkTracking)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

#Preview {
    RootView()
}
