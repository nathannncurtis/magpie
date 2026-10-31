import SwiftUI

/// The installed mark on a mod row: a 30 pt circle in the sheen with an `onSheen` check
/// (03 · Installed check). It is the one place in the flow that pops.
struct InstalledCheck: View {

    private enum Layout {
        static let side: CGFloat = 30
        static let check: CGFloat = 13
        static let popFrom: CGFloat = 0.5
    }

    /// Whether the check lands with the snap pop; the plain state stays still.
    var pops = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.sheen)
            Image(systemName: "checkmark")
                .font(.system(size: Layout.check, weight: .semibold))
                .foregroundStyle(Palette.onSheen)
        }
        .frame(width: Layout.side, height: Layout.side)
        .scaleEffect(shown || !pops ? 1 : Layout.popFrom)
        .onAppear {
            guard pops, !reduceMotion else {
                shown = true
                return
            }
            withAnimation(Springs.snap.animation) {
                shown = true
            }
        }
        .accessibilityLabel(Text(String(localized: "Installed")))
        .accessibilityIdentifier("mods.installedCheck")
    }
}

#Preview {
    InstalledCheck(pops: true)
        .padding(20)
}
