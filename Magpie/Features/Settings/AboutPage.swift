import SwiftUI

/// About Magpie (04 · 11): the version, the license, and where the source lives.
struct AboutPage: View {
    var body: some View {
        SettingsScaffold(title: String(localized: "About Magpie"), showsBack: true) {
            GroupedBox {
                SettingsRow(icon: .symbol("info.circle"), title: String(localized: "Version")) {
                    value(Self.version)
                }
                SettingsRow(icon: .symbol("doc.text"), title: String(localized: "License")) {
                    value("MPL-2.0")
                }
                .divided(true)
                .accessibilityIdentifier("settings.about.licence")
                SettingsRow(icon: .symbol("link"), title: String(localized: "Source code")) {
                    Image(systemName: "arrow.up.right")
                        .font(Typography.icon(.small))
                        .foregroundStyle(Palette.textOnMistSecondaryMeta)
                }
                .action { openSource() }
                .divided(true)
                .accessibilityIdentifier("settings.about.source")
            }

            Text("Free and open source. No account. Nothing collected.")
                .font(Typography.small)
                .foregroundStyle(Palette.textOnMistSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 18)
                .padding(.horizontal, Metrics.Spacing.insetList)
        }
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(Typography.row)
            .foregroundStyle(Palette.textOnMistSecondaryMeta)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func openSource() {
        guard let url = URL(string: "https://github.com/nathannncurtis/magpie") else { return }
        UIApplication.shared.open(url)
    }
}
