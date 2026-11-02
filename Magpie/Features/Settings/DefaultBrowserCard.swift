import SwiftUI

/// The card at the top of Settings until Magpie is the default browser (03 · Settings,
/// 04 · 11): the group's frosted material, a line about what it gives, and the ink "Open"
/// capsule that jumps to the place iOS decides it.
struct DefaultBrowserCard: View {
    @Environment(\.scenePhase) private var scenePhase
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
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Palette.ink)
                    )
                    // The capsule keeps its size; the target around it meets the 44 pt
                    // least.
                    .frame(minWidth: Metrics.tapTarget, minHeight: Metrics.tapTarget)
                    .contentShape(.rect)
                    .accessibilityIdentifier("settings.defaultBrowser.open")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .groupedSurface()
            .padding(.horizontal, Metrics.Spacing.insetList)
            .accessibilityIdentifier("settings.defaultBrowser")
            .task { refresh() }
            .onChange(of: scenePhase) { _, phase in
                // The user may have just made Magpie the default in iOS Settings, which
                // is where the card sends them; look again on the way back in.
                guard phase == .active else { return }
                refresh()
            }
        }
    }

    /// Whether iOS counts Magpie as the default browser.
    private func refresh() {
        isDefault = (try? UIApplication.shared.isDefault(.webBrowser)) ?? false
    }

    private func openDefaultBrowserSettings() {
        guard
            let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString)
        else { return }
        UIApplication.shared.open(url)
    }
}
