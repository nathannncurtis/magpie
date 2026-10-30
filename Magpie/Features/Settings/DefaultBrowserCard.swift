import SwiftUI

/// The card at the top of Settings until Magpie is the default browser (03 · Settings,
/// 04 · 11): the group's frosted material, a line about what it gives, and the ink "Open"
/// capsule that jumps to the place iOS decides it.
struct DefaultBrowserCard: View {
    @State private var isDefault = false

    var body: some View {
        if !isDefault {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make Magpie your default browser")
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                    Text("Links from other apps open here. Set in iOS Settings.")
                        .font(Typography.small)
                        .foregroundStyle(Palette.textOnMistSecondary)
                        .lineSpacing(1)
                }
                Spacer(minLength: 8)
                Button("Open") { openDefaultBrowserSettings() }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Palette.ink)
                    )
                    .accessibilityIdentifier("settings.defaultBrowser.open")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
                    .strokeBorder(Palette.groupHairline, lineWidth: 0.75)
            )
            .padding(.horizontal, Metrics.Spacing.insetList)
            .accessibilityIdentifier("settings.defaultBrowser")
            .task { isDefault = (try? UIApplication.shared.isDefault(.webBrowser)) ?? false }
        }
    }

    private func openDefaultBrowserSettings() {
        guard
            let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString)
        else { return }
        UIApplication.shared.open(url)
    }
}
