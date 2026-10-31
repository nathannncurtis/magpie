import SwiftUI

/// The glass footer pill that opens the install-from-URL sheet (03 · Install footer).
struct InstallFooter: View {

    private enum Layout {
        static let height = Metrics.Bar.installFooterHeight
        static let icon: CGFloat = 18
        static let gap: CGFloat = 8
    }

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.gap) {
                Image(systemName: "link")
                    .font(.system(size: Layout.icon, weight: .medium))
                Text(String(localized: "Install from URL"))
                    .font(Typography.buttonPill)
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.height)
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
