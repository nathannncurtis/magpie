import SwiftUI

/// The glass footer pill that opens the install-from-URL sheet (03 · Install footer).
struct InstallFooter: View {

    private enum Layout {
        static let height = Metrics.Bar.installFooterHeight
        static let gap: CGFloat = 8
    }

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.gap) {
                Image(systemName: "link")
                    .font(Typography.icon(.regular))
                Text(String(localized: "Install from URL"))
                    .font(Typography.buttonPill)
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity)
            // Grows under Dynamic Type instead of clipping the label.
            .frame(minHeight: Layout.height)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("mods.installFooter")
    }
}

#Preview {
    InstallFooter {}
        .padding(20)
}
