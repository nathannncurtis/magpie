import SwiftUI

/// The engine list Settings pushes from "Search engine" (04 · 11): the eight choices of
/// the first-launch picker, as rows. Picking a built-in saves it and goes back; picking
/// Other asks for a search URL containing %s and validates it first.
struct EngineListPage: View {
    @Environment(\.dismiss) private var dismiss
    let preferences: Preferences

    @State private var showsOtherField = false
    @State private var otherURL = ""

    var body: some View {
        SettingsScaffold(title: "Search engine", showsBack: true) {
            SettingsGroup {
                ForEach(Array(SearchEngine.builtins.enumerated()), id: \.element.id) {
                    index, engine in
                    builtinRow(engine, isDivided: index > 0)
                        .accessibilityIdentifier("settings.engineList.\(engine.id)")
                }
                otherRow
                    .accessibilityIdentifier("settings.engineList.other")
            }
            if showsOtherField {
                otherField
                    .padding(.top, 12)
            }
        }
    }

    private func builtinRow(_ engine: SearchEngine, isDivided: Bool) -> some View {
        SettingsRow(icon: .favicon("engine-\(engine.id)"), title: engine.displayName) {
            checkmark(if: preferences.searchEngine.id == engine.id)
        }
        .divided(isDivided)
        .action {
            preferences.searchEngine = engine
            dismiss()
        }
        .accessibilityAddTraits(preferences.searchEngine.id == engine.id ? .isSelected : [])
    }

    private var otherRow: some View {
        SettingsRow(icon: .otherEngine, title: "Other") {
            checkmark(if: preferences.searchEngine.id == "other")
        }
        .divided(true)
        .action {
            if preferences.searchEngine.id == "other" {
                dismiss()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { showsOtherField = true }
            }
        }
        .accessibilityAddTraits(preferences.searchEngine.id == "other" ? .isSelected : [])
    }

    private func checkmark(if selected: Bool) -> some View {
        Group {
            if selected {
                SettingsCheckmark()
            }
        }
    }

    /// The URL entry under the list, once Other is tapped.
    private var otherField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                // COPY: review — 06 has this line to write.
                "Search URL, with %s for the query",
                text: $otherURL
            )
            .font(Typography.field)
            .foregroundStyle(Palette.textPrimary)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.searchFieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        otherIsValid ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.engineTileOtherOutline),
                        lineWidth: 1)
            )
            .accessibilityIdentifier("settings.otherURL")

            if !otherURL.isEmpty && !otherIsValid {
                Text("The address needs %s where the query goes.")
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    // In line with the field's text, not its box.
                    .padding(.horizontal, 14)
            }

            Button("Use this URL") { saveOther() }
                .font(Typography.buttonPill)
                .foregroundStyle(otherIsValid ? Palette.teal : Palette.textTertiary)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(.rect)
                .disabled(!otherIsValid)
                .accessibilityIdentifier("settings.otherSave")
        }
        .padding(.horizontal, Metrics.Spacing.insetList)
    }

    private var validatedOther: SearchEngine? {
        SearchEngine.other(template: otherURL)
    }

    private var otherIsValid: Bool {
        validatedOther != nil
    }

    private func saveOther() {
        guard let other = validatedOther else { return }
        preferences.searchEngine = other
        dismiss()
    }
}
