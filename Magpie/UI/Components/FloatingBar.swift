import SwiftUI

/// What a floating bar sits on.
enum FloatingBarSurface {
    /// No glass of its own: the contents carry theirs (the chip, the + button).
    case clear
    /// A glass capsule, optionally page-tinted and optionally reacting to touch.
    case glass(tint: Color? = nil, interactive: Bool = false)
}

/// The one shell every floating bar and bottom row wears: the Tabs and Launch rows, the
/// Archive, Bookmarks and History search pills, the Skim control bar and the reading bar.
/// It fixes what they share — the height, the side inset, the glass, a width cap that
/// centres the bar on wide screens — and leaves the contents to the caller. The bottom
/// edge is `floatingBarBottomEdge(safeAreaBottom:)`, applied outside.
struct FloatingBar<Content: View>: View {

    var surface: FloatingBarSurface = .clear
    /// An exact height (the reading bar's collapse drives it); nil takes the standard
    /// one, which grows with the type size.
    var height: CGFloat?
    /// The gap to the screen sides.
    var sideInset: CGFloat = Metrics.Spacing.insetFloating
    /// Padding inside the capsule, before the contents.
    var contentInset: CGFloat = 0
    /// Names the glass so a later pass can morph it into a sheet.
    var glassNamespace: Namespace.ID?
    @ViewBuilder var content: Content

    @ScaledMetric(relativeTo: .subheadline) private var scaledHeight = Metrics.Bar.height

    private var standardHeight: CGFloat { max(Metrics.Bar.height, scaledHeight) }

    var body: some View {
        sized
            .modifier(BarSurface(surface: surface, namespace: glassNamespace))
            .frame(maxWidth: Metrics.Bar.maxWidth)
            .padding(.horizontal, sideInset)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sized: some View {
        let padded = content.padding(.horizontal, contentInset)
        if let height {
            padded.frame(maxWidth: .infinity).frame(height: height)
        } else {
            padded.frame(maxWidth: .infinity).frame(minHeight: standardHeight)
        }
    }
}

/// Paints the bar's surface.
private struct BarSurface: ViewModifier {
    let surface: FloatingBarSurface
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        switch surface {
        case .clear:
            content
        case .glass(let tint, let interactive):
            let shaped = content.glassEffect(glass(tint: tint, interactive: interactive), in: .capsule)
            if let namespace {
                shaped.glassEffectID(ChromeGlassID.chrome, in: namespace)
            } else {
                shaped
            }
        }
    }

    private func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Three fixed slots: leading hugs the left, trailing the right, and the centre holds
/// the middle of the bar whatever the sides measure. A + in the centre slot is
/// therefore centred on every row that has one, and a flexible centre (a URL) takes
/// what the wider side leaves.
struct FloatingBarSlots<Leading: View, Centre: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var centre: Centre
    @ViewBuilder var trailing: Trailing

    var body: some View {
        SlotLayout {
            // Each slot is wrapped so an empty one still counts as a slot.
            ZStack { leading }
            ZStack { centre }
            ZStack { trailing }
        }
    }

    private struct SlotLayout: Layout {
        /// The least gap between a side and the centre.
        private let gap = Metrics.Spacing.unit * 2

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard subviews.count == 3 else { return .zero }
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let side = max(sizes[0].width, sizes[2].width)
            let ideal = 2 * (side + gap) + sizes[1].width
            let height = sizes.map(\.height).max() ?? 0
            return CGSize(width: proposal.width ?? ideal, height: height)
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
        ) {
            guard subviews.count == 3 else { return }
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let side = max(sizes[0].width, sizes[2].width)
            let centreWidth = max(0, bounds.width - 2 * (side + gap))
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: side, height: bounds.height))
            subviews[1].place(
                at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                proposal: ProposedViewSize(width: centreWidth, height: bounds.height))
            subviews[2].place(
                at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                proposal: ProposedViewSize(width: side, height: bounds.height))
        }
    }
}

extension View {
    /// Lifts a bar to the shared bottom edge: clear of the home indicator on every
    /// device, from the same metric the menu's pinned row reads.
    func floatingBarBottomEdge(safeAreaBottom: CGFloat) -> some View {
        padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: safeAreaBottom))
    }
}

#Preview {
    VStack {
        Spacer()
        FloatingBar {
            FloatingBarSlots {
                ArchivedChip(count: 12, action: {})
            } centre: {
                PlusButton(action: {})
            } trailing: {
                Text("3 open").font(Typography.small)
            }
        }
        .floatingBarBottomEdge(safeAreaBottom: 34)
    }
    .background(MistBackground())
}
