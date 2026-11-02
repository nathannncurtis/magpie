import SwiftUI

/// The archive interval picker Settings pushes (04 · 11): the steps as rows, a checkmark
/// on the chosen one. Picking saves and goes back.
struct ArchivePickerPage: View {
    @Environment(\.dismiss) private var dismiss
    let preferences: Preferences

    var body: some View {
        SettingsScaffold(title: String(localized: "Archive tabs after"), showsBack: true) {
            GroupedBox {
                ForEach(
                    Array(Preferences.archiveIntervalSteps.enumerated()),
                    id: \.offset
                ) { index, step in
                    SettingsRow(icon: .symbol("archivebox"), title: Preferences.archiveIntervalLabel(step)) {
                        if preferences.archiveInterval == step {
                            SettingsCheckmark()
                        }
                    }
                    .divided(index > 0)
                    .action {
                        preferences.archiveInterval = step
                        dismiss()
                    }
                    .accessibilityAddTraits(
                        preferences.archiveInterval == step ? .isSelected : []
                    )
                    .accessibilityIdentifier("settings.archiveStep.\(index)")
                }
            }
        }
    }
}
