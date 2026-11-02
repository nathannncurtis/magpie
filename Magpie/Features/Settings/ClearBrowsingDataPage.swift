import SwiftUI

/// The Clear browsing data page Settings pushes (04 · 11): what to clear as three
/// switches, all on, and a destructive Clear beneath that asks once more.
struct ClearBrowsingDataPage: View {
    @Environment(AppModel.self) private var model
    @State private var kinds = BrowsingDataKinds()
    @State private var confirms = false
    @State private var isClearing = false
    @State private var didClear = false

    var body: some View {
        SettingsScaffold(title: String(localized: "Clear browsing data"), showsBack: true) {
            GroupedBox {
                SettingsToggleRow(
                    icon: .symbol("clock"), title: String(localized: "History"),
                    isOn: binding(\.history)
                )
                .accessibilityIdentifier("settings.clearData.history")
                SettingsToggleRow(
                    icon: .cookie, title: String(localized: "Cookies and site data"),
                    isOn: binding(\.cookiesAndSiteData)
                )
                .divided()
                .accessibilityIdentifier("settings.clearData.cookies")
                SettingsToggleRow(
                    icon: .symbol("internaldrive"), title: String(localized: "Cache"),
                    isOn: binding(\.cache)
                )
                .divided()
                .accessibilityIdentifier("settings.clearData.cache")
            }

            Button(role: .destructive) {
                confirms = true
            } label: {
                Text(String(localized: "Clear"))
                    .font(Typography.row)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, minHeight: Metrics.Spacing.rowSettings)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(
                            cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(kinds.isEmpty || isClearing)
            .opacity(kinds.isEmpty ? 0.4 : 1)
            .padding(.horizontal, Metrics.Spacing.insetList)
            .padding(.top, 16)
            .accessibilityIdentifier("settings.clearData.clear")

            if didClear {
                // COPY: review — drafted, not on the boards.
                Text(String(localized: "Cleared."))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textOnMistSecondaryMeta)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .accessibilityIdentifier("settings.clearData.done")
            }
        }
        .confirmationDialog(
            String(localized: "Clear browsing data?"),
            isPresented: $confirms,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear"), role: .destructive) {
                clear()
            }
            .accessibilityIdentifier("settings.clearData.confirm")
        } message: {
            Text(String(localized: "This can't be undone. Open pages reload."))
        }
    }

    private func binding(_ keyPath: WritableKeyPath<BrowsingDataKinds, Bool>) -> Binding<Bool> {
        Binding(
            get: { kinds[keyPath: keyPath] },
            set: {
                kinds[keyPath: keyPath] = $0
                didClear = false
            })
    }

    private func clear() {
        isClearing = true
        Task {
            await model.clearBrowsingData(kinds)
            isClearing = false
            didClear = true
        }
    }
}
