import SwiftUI

/// The URL pill (03 · Chrome): the host alone, centred, which grows to fill the bar.
/// Tapping it opens search. A lock shows only on errors; HTTPS is assumed otherwise.
struct URLPill: View {

    /// The host to show, already formatted for display.
    let host: String

    /// How far the bar has collapsed: 0 in the full bar, 1 in the slim pill.
    var collapse: CGFloat = 0

    /// Whether the error lock shows.
    var showsLock = false

    let action: () -> Void

    /// The pill's height in the full bar.
    private static let fullHeight: CGFloat = 48
    /// The pill's height in the slim pill.
    private static let slimHeight: CGFloat = 30
    /// The least the pill's tap target measures, whatever its visual height: the slim
    /// pill looks 30 tall and must still take a full-size tap.
    private static let minHitHeight: CGFloat = 44
    /// The lock glyph, only shown on errors.
    private static let lockSize: CGFloat = 13
    /// The gap between the lock and the host.
    private static let gap: CGFloat = 8

    private var height: CGFloat {
        Self.fullHeight - (Self.fullHeight - Self.slimHeight) * collapse
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.gap) {
                if showsLock {
                    Image(systemName: "lock.fill")
                        .font(.system(size: Self.lockSize, weight: .medium))
                        .imageScale(.medium)
                }
                ZStack {
                    text(Typography.row.weight(.medium)).opacity(1 - collapse)
                    text(Typography.meta.weight(.medium)).opacity(collapse)
                }
            }
            .frame(minHeight: max(Self.minHitHeight, height))
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(host))
    }

    /// One of the two crossfading host texts: full size in the bar, smaller in the pill.
    private func text(_ font: Font) -> some View {
        Text(host)
            .font(font)
            .lineLimit(1)
    }
}

#Preview("Full") {
    URLPill(host: "quietweb.org") {}
        .foregroundStyle(Color(hex: 0x3A2E26))
        .padding(20)
}

#Preview("Slim") {
    URLPill(host: "quietweb.org", collapse: 1) {}
        .foregroundStyle(Color(hex: 0x3A2E26))
        .padding(20)
}
