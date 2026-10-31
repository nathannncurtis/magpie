import SwiftUI

/// Pick a search engine, the second screen of the first launch (04 · 07b): the tiles,
/// two per row, nothing pre-selected. Picking Other asks for its search URL first; the
/// CTA stays disabled until a valid choice stands.
struct EnginePickerScreen: View {
    let preferences: Preferences
    var onContinue: () -> Void

    @State private var picked: PickableEngine?
    @State private var otherURL = ""
    /// The bottom inset, read before the layout goes full-bleed: the container ignores
    /// the bottom safe area, and inside it the inset can no longer be read.
    @State private var bottomInset: CGFloat = 0
    @FocusState private var otherFieldFocused: Bool

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
            // With the keys up the grid scrolls under the header; it softens there rather
            // than cutting tiles mid-line.
            .scrollEdgeEffectStyle(.soft, for: .top)

            PrimaryCTA(
                title: continueTitle,
                isDisabled: chosenEngine == nil,
                action: save
            )
            .padding(.horizontal, 16)
            .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset))
            .padding(.top, 12)
            .accessibilityIdentifier("picker.continue")
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: { inset in
            // The keys swell the bottom inset while Other's field is focused; the
            // resting edge is what the CTA is seated from, and it keeps its place
            // above the keys either way.
            guard !otherFieldFocused else { return }
            bottomInset = inset
        }
        // The CTA measures from the physical bottom edge (01 · Bottom controls): the
        // container runs on under the home indicator and the padding seats it above
        // that edge, while the keys still lift the field.
        .ignoresSafeArea(.container, edges: .bottom)
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
            .focused($otherFieldFocused)
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
                    // In line with the field's text, not its box.
                    .padding(.horizontal, 14)
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
