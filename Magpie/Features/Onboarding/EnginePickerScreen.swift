import SwiftUI

/// Pick a search engine, the second screen of the first launch (04 · 07b): the tiles,
/// two per row, nothing pre-selected. Picking Other asks for its search URL first; the
/// CTA stays disabled until a valid choice stands.
struct EnginePickerScreen: View {
    let preferences: Preferences
    var onContinue: () -> Void

    @State private var picked: PickableEngine?
    @State private var otherURL = ""

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepLabel(title: "Search")
                // 26 below the safe-area top: the gap holds wherever the status bar ends.
                .padding(.top, 26)
            Text("Where should searches go?")
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.Spacing.insetList + 4)
                .padding(.top, 8)
            Text("Pick one; you can switch any time from the menu.")
                .font(Typography.row)
                .foregroundStyle(Palette.textOnMistSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.Spacing.insetList + 4)
                .padding(.top, 8)
                .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: tileColumns, spacing: 10) {
                    ForEach(PickableEngine.all) { engine in
                        EngineTile(engine: engine, isSelected: picked == engine) {
                            pick(engine)
                        }
                    }
                }
                .padding(.horizontal, Metrics.Spacing.insetList)
                if picked == .other {
                    otherField
                        .padding(.top, 12)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            PrimaryCTA(
                title: continueTitle,
                isDisabled: chosenEngine == nil,
                action: save
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 26)
            .padding(.top, 12)
            .accessibilityIdentifier("picker.continue")
        }
    }

    private var tileColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]
    }

    private var continueTitle: String {
        guard let chosenEngine else { return "Continue" }
        return String(localized: "Continue with \(chosenEngine.displayName)")
    }

    /// The engine that would be saved: the tile picked, or Other once its URL validates.
    private var chosenEngine: SearchEngine? {
        switch picked {
        case .builtin(let engine):
            engine
        case .other:
            SearchEngine.other(template: otherURL)
        case nil:
            nil
        }
    }

    private func pick(_ engine: PickableEngine) {
        picked = engine
    }

    /// The URL entry under the grid, while Other is picked.
    private var otherField: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        chosenEngine != nil
                            ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.engineTileOtherOutline),
                        lineWidth: 1)
            )
            .accessibilityIdentifier("picker.otherURL")

            if !otherURL.isEmpty && chosenEngine == nil {
                Text("The address needs %s where the query goes, on http or https.")
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
            }
        }
        .padding(.horizontal, Metrics.Spacing.insetList)
    }

    private func save() {
        guard let engine = chosenEngine else { return }
        preferences.searchEngine = engine
        onContinue()
    }
}
