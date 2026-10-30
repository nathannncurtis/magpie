import SwiftUI

/// The archive interval picker Settings pushes (04 · 11): the steps as rows, a checkmark
/// on the chosen one. Picking saves and goes back.
struct ArchivePickerPage: View {
    @Environment(\.dismiss) private var dismiss
    let preferences: Preferences

    var body: some View {
        SettingsScaffold(title: "Archive tabs after", showsBack: true) {
            SettingsGroup {
                ForEach(
                    Array(Preferences.archiveIntervalSteps.enumerated()),
                    id: \.offset
                ) { index, step in
                    SettingsRow(icon: .symbol("archivebox"), title: Preferences.archiveIntervalLabel(step)) {
                        if preferences.archiveInterval == step {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    .divided(index > 0)
                    .action {
                        preferences.archiveInterval = step
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.archiveStep.\(index)")
                }
            }
        }
    }
}
