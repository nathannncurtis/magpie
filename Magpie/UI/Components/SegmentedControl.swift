import SwiftUI

/// A two-way segmented control on glass: a 38 pt capsule track (taller under Dynamic
/// Type), 3 pt inset, and the selected segment a solid card thumb with a small shadow.
/// Each segment's tap target holds at 44 tall, taller than the track itself (03 ·
/// Segmented control).
struct SegmentedControl: View {

    /// Layout numbers from the board.
    private enum Layout {
        static let height: CGFloat = 38
        static let inset: CGFloat = 3
        /// The least a segment offers a finger, per the board's tap-target floor.
        static let hitHeight: CGFloat = 44
    }

    /// The segments' labels, in order.
    let options: [String]
    @Binding var selection: Int

    /// The track's height, growing with Dynamic Type the way its labels do.
    @ScaledMetric(relativeTo: .footnote) private var scaledTrackHeight = Layout.height
    /// Grows with the type size, never below the board's height at the smaller sizes.
    private var trackHeight: CGFloat { max(Layout.height, scaledTrackHeight) }

    @Namespace private var thumb
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                segment(index)
            }
        }
        .padding(.horizontal, Layout.inset)
        .frame(height: trackHeight)
        .glassEffect(.regular, in: .capsule)
    }

    private func segment(_ index: Int) -> some View {
        let selected = index == selection
        return Button {
            withAnimation(Springs.settle.animation) {
                selection = index
            }
        } label: {
            Text(options[index])
                .font(Typography.meta.weight(.semibold))
                .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if selected {
                        Capsule()
                            .fill(Palette.card)
                            .shadow(color: thumbShadow, radius: 3, y: 1)
                            .matchedGeometryEffect(id: "segment.thumb", in: thumb)
                    }
                }
                // The hit area, standing taller than the track it sits on: the frame is
                // centred in the track, so the visuals stay the board's and a finger
                // still gets its 44 pt.
                .frame(minHeight: Layout.hitHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("segment.\(index)")
    }

    /// The thumb's small shadow; dark's thumb carries none.
    private var thumbShadow: Color {
        colorScheme == .dark ? .clear : .black.opacity(0.12)
    }
}

#Preview {
    struct Host: View {
        @State private var selection = 0

        var body: some View {
            SegmentedControl(options: ["Directory", "Installed · 3"], selection: $selection)
                .padding(20)
        }
    }
    return Host()
}
