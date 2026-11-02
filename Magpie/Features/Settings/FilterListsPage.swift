import SwiftUI

/// The filter lists page Settings pushes (04 · 11): each list with when it last
/// refreshed, and "Update now" beneath.
struct FilterListsPage: View {
    let blocker: ContentBlocker

    @State private var updates: [FilterListUpdate] = []

    var body: some View {
        SettingsScaffold(title: String(localized: "Filter lists"), showsBack: true) {
            GroupedBox {
                ForEach(Array(updates.enumerated()), id: \.element.id) { index, update in
                    SettingsRow(icon: .symbol("list.bullet.rectangle"), title: update.list.title) {
                        Text(ContentBlocker.updatedText(from: update.updated, now: .now))
                            .font(Typography.row)
                            .foregroundStyle(Palette.textOnMistSecondaryMeta)
                    }
                    .divided(index > 0)
                    .accessibilityIdentifier("settings.filterList.\(update.list.id)")
                }
                SettingsRow(icon: .symbol("arrow.clockwise"), title: String(localized: "Update now")) {
                    EmptyView()
                }
                .divided(!updates.isEmpty)
                .action {
                    Task {
                        await blocker.updateNow()
                        updates = await blocker.listUpdates()
                    }
                }
                .accessibilityIdentifier("settings.updateNow")
            }
        }
        .task { updates = await blocker.listUpdates() }
    }
}
