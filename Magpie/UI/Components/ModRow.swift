import SwiftUI

/// One mod in a card of rows: the icon, the name, the description, the author line, and
/// what sits at the trailing edge — Get, the installed check, or an on/off switch
/// (03 · Mod row).
struct ModRow: View {

    @Environment(\.colorScheme) private var colorScheme

    /// What sits at the row's trailing edge.
    enum Trailing {
        case get(action: () -> Void)
        /// The mark while the mod's file is fetched and checked (05 · 06).
        case fetching
        case installed(pops: Bool)
        case toggle(isOn: Binding<Bool>)

        var isToggle: Bool {
            if case .toggle = self { true } else { false }
        }
    }

    /// Layout numbers from the board.
    private enum Layout {
        static let gap: CGFloat = 12
        static let verticalPadding: CGFloat = 11
        static let swipeOpenWidth: CGFloat = 92
        static let swipeTrigger: CGFloat = 56
        /// The mark the row carries while its install runs.
        static let spinner: CGFloat = 24
        /// The slot Get, the spinner and the check share, about Get's own width: the
        /// check is narrower, and without the slot the summary would rewrap and the
        /// row change height the moment an install lands.
        static let actionSlot: CGFloat = 60
    }

    let icon: ModIconSpec
    let name: String
    let summary: String?
    let authorLine: String?
    /// The "Not reviewed" tag beside the name, for a link install.
    var notReviewed = false
    let trailing: Trailing
    /// The swipe-left action, on installed rows only.
    var onRemove: (() -> Void)? = nil

    @State private var swipeOffset: CGFloat = 0
    /// The tag's size, scaling with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var tagSize: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            // Mounted only while the row is actually aside: at rest nothing sits
            // behind it to edge out past its rounded corners. Settling back to 0
            // inside withAnimation fades it out in step with the row's slide.
            if onRemove != nil, swipeOffset < 0 {
                removeBehind
            }
            row
                .offset(x: swipeOffset)
                .gesture(drag)
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: Layout.gap) {
            ModIcon(spec: icon)
                .accessibilityHidden(true)
            // The text reads as one line; what trails it stays its own element, so
            // Get and the on/off switch stay reachable.
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if notReviewed {
                        notReviewedTag
                    }
                }
                if let summary {
                    Text(summary)
                        .font(Typography.small)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                if let authorLine {
                    Text(authorLine)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .removeAction(onRemove)
            Spacer(minLength: 0)
            trailingView
                .frame(minWidth: trailing.isToggle ? nil : Layout.actionSlot, alignment: .trailing)
        }
        .padding(.vertical, Layout.verticalPadding)
        // The card's own colour, so the row is opaque: the swipe action under it shows
        // only where a swipe has moved the row aside, never through empty space.
        .background(Palette.card)
        // A container, so the row's name stays its own and the Get button and switch
        // inside keep theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mods.row")
    }

    private var notReviewedTag: some View {
        Text(String(localized: "Not reviewed"))
            .font(.system(size: tagSize, weight: .semibold))
            .foregroundStyle(Palette.warningText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Palette.warningBackground, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("mods.notReviewed")
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .get(let action):
            GetButton(action: action)
        case .fetching:
            MarkSpinner(size: Layout.spinner)
                .accessibilityElement()
                .accessibilityLabel(Text(ModsCopy.installing))
        case .installed(let pops):
            InstalledCheck(pops: pops)
        case .toggle(let isOn):
            ModSwitch(isOn: isOn)
                .accessibilityLabel(Text(name))
        }
    }

    /// What a left swipe reveals.
    private var removeBehind: some View {
        Text(String(localized: "Remove"))
            .font(Typography.rowTitle)
            // White on light teal; dark's bright teal needs dark text (1.5:1 in white).
            .foregroundStyle(colorScheme == .dark ? Palette.onInk : .white)
            .frame(width: Layout.swipeOpenWidth, alignment: .center)
            .frame(maxHeight: .infinity)
            // Rounded to the card's radius, the shape that covers it: a square
            // tile would reach past the row's rounded ends at the corners.
            .background(
                Palette.teal,
                in: RoundedRectangle(
                    cornerRadius: Metrics.Radius.card,
                    style: .continuous)
            )
            .accessibilityIdentifier("mods.remove")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard onRemove != nil, abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                swipeOffset = min(0, max(-Layout.swipeOpenWidth, value.translation.width))
            }
            .onEnded { value in
                guard onRemove != nil else { return }
                if value.translation.width < -Layout.swipeTrigger {
                    onRemove?()
                }
                withAnimation(reduceMotion ? nil : Springs.settle.animation) {
                    swipeOffset = 0
                }
            }
    }
}

/// The swipe-left action, named for VoiceOver: the gesture itself is invisible to it,
/// so the row's line carries the action instead.
private extension View {

    @ViewBuilder
    func removeAction(_ action: (() -> Void)?) -> some View {
        if let action {
            accessibilityAction(named: Text(ModsCopy.remove), action)
        } else {
            self
        }
    }
}

/// The row's on/off switch, as the board draws it: 50 by 30, ink when on and flipping to
/// paper after sunset.
private struct ModSwitch: View {

    private enum Layout {
        static let width: CGFloat = 50
        static let height: CGFloat = 30
        static let knob: CGFloat = 26
        static let inset: CGFloat = 2
    }

    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : Springs.settle.animation) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.toggleOff))
                Circle()
                    .fill(knob)
                    .frame(width: Layout.knob, height: Layout.knob)
                    .padding(Layout.inset)
            }
            .frame(width: Layout.width, height: Layout.height)
            // A 44 pt hit target; the negative padding keeps the layout the board's.
            .padding(.vertical, 7)
            .contentShape(.rect)
            .padding(.vertical, -7)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text(String(localized: "On")) : Text(String(localized: "Off")))
        .accessibilityIdentifier("mods.toggle")
    }

    private var knob: Color {
        if isOn { return Palette.onInk }
        return colorScheme == .dark ? Palette.paper : .white
    }
}
