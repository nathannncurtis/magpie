import SwiftUI

/// The onboarding pieces (03 · Onboarding): the primary CTA, an engine tile, and the step
/// label.
struct PrimaryCTA: View {
    let title: String
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.Bar.primaryCTAHeight)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.ink)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}

/// The uppercase step label above the picker's question.
// COPY: review — the boards show no step-label wording.
struct OnboardingStepLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.labelOnMist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One engine in the picker's grid (03 · Onboarding): glass, 92 tall, the favicon top
/// left, the name and note at the bottom. Selected: a 2 pt ink ring, an ink check badge,
/// and a more opaque fill. The Other tile drops the glass for an outline.
struct EngineTile: View {
    let engine: PickableEngine
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                tileFill
                if case .builtin(let searchEngine) = engine {
                    Image("engine-\(searchEngine.id)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.engineTileOtherGlyph)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .frame(width: 30, height: 30)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.title)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(engine.note)
                        .font(Typography.small)
                        .foregroundStyle(Palette.textOnMistSecondaryMeta)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(height: 92)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Metrics.Radius.tile, style: .continuous)
                        .stroke(Palette.ink, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    checkBadge
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("picker.tile.\(engine.id)")
    }

    /// The tile's background: glass, denser once picked with the ink ring, or Other's
    /// outline.
    @ViewBuilder private var tileFill: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.tile, style: .continuous)
        if case .other = engine {
            shape
                .fill(Palette.engineTileOther)
                .overlay(
                    shape.strokeBorder(Palette.engineTileOtherOutline, lineWidth: 1))
        } else if isSelected {
            shape
                .fill(Palette.engineTileSelected)
        } else {
            shape
                .fill(Palette.engineTile)
                .overlay(shape.strokeBorder(Palette.engineTileHairline, lineWidth: 0.75))
        }
    }

    /// The 22 pt ink circle with the check, top right.
    private var checkBadge: some View {
        ZStack {
            Circle()
                .fill(Palette.ink)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.onInk)
        }
        .frame(width: 22, height: 22)
        .padding(12)
    }
}

/// What the picker's grid holds: a built-in engine, or Other with its one-line note.
enum PickableEngine: Identifiable, Equatable {
    case builtin(SearchEngine)
    case other

    var id: String {
        switch self {
        case .builtin(let engine): engine.id
        case .other: "other"
        }
    }

    var title: String {
        switch self {
        case .builtin(let engine): engine.displayName
        case .other: "Other"
        }
    }

    /// The one-line note under the name (04 · 07b).
    var note: String {
        switch self {
        case .builtin(let engine): Self.notes[engine.id] ?? ""
        case .other: "Any, by search URL"
        }
    }

    private static let notes = [
        "duckduckgo": "No tracking",
        "google": "The usual",
        "brave": "Own index",
        "kagi": "Paid, no ads",
        "ecosia": "Plants trees",
        "startpage": "Google, privately",
        "bing": "Microsoft",
    ]

    /// The grid's fixed order: the seven built-ins, then Other.
    static let all: [PickableEngine] = SearchEngine.builtins.map(PickableEngine.builtin) + [.other]
}
