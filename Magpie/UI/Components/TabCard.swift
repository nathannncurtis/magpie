import SwiftUI
import UIKit

/// One card in the tab stack: the page snapshot at 62% of the screen's scale, in a
/// 5 pt white ring with an outer hairline and the soft shadow. The size comes from the
/// stack; the card only fills what it is given.
///
/// A `namespace` wires the card into the page ↔ card transition: both geometry effects
/// are keyed by the tab id, so the reading screen can match against it.
struct TabCard: View {
    let tab: Tab
    var snapshot: Data?
    var namespace: Namespace.ID?

    private enum CardMetrics {
        /// The white ring around the snapshot, and the hairline outside it.
        static let ringWidth: CGFloat = 5
        static let hairlineWidth: CGFloat = 0.75
        /// The soft shadow under a solid card: y 14, blur 30.
        static let shadowRadius: CGFloat = 15
        static let shadowY: CGFloat = 14
    }

    var body: some View {
        matched(
            content
                .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.tabCard, style: .continuous))
                .shadow(
                    color: shadowColor,
                    radius: CardMetrics.shadowRadius,
                    y: CardMetrics.shadowY
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.tabCard, style: .continuous)
                        .stroke(ringColor, lineWidth: CardMetrics.ringWidth)
                        .padding(-CardMetrics.ringWidth / 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.tabCard, style: .continuous)
                        .stroke(hairlineColor, lineWidth: CardMetrics.hairlineWidth)
                        .padding(
                            -(CardMetrics.ringWidth + CardMetrics.hairlineWidth / 2))))
    }

    @ViewBuilder
    private var content: some View {
        if let image = snapshot.flatMap(UIImage.init(data:)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    /// What the card shows until the first snapshot lands.
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.Radius.tabCard, style: .continuous)
                .fill(Palette.card)
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                if let host = tab.host {
                    Text(host)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func matched(_ view: some View) -> some View {
        if let namespace {
            view
                .matchedGeometryEffect(id: tab.id, in: namespace)
                .matchedTransitionSource(id: tab.id, in: namespace)
        } else {
            view
        }
    }

    private var ringColor: Color {
        Palette.tabCardRing
    }

    private var hairlineColor: Color {
        Palette.tabCardHairline
    }

    private var shadowColor: Color {
        Palette.tabCardShadow
    }
}

#Preview("Snapshot") {
    let snapshot = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 500)).pngData { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(origin: .zero, size: CGSize(width: 240, height: 500)))
    }
    TabCard(tab: Tab(title: "The web, read slowly", lastActive: .now), snapshot: snapshot)
        .frame(width: 240, height: 500)
        .padding(40)
}

#Preview("Placeholder") {
    TabCard(
        tab: Tab(url: URL(string: "https://en.wikipedia.org/wiki/Carbon_steel"), lastActive: .now)
    )
    .frame(width: 240, height: 500)
    .padding(40)
}
