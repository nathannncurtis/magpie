import SwiftUI
import UIKit

/// One card in the tab stack: the page snapshot at 62% of the screen's scale, in a
/// 5 pt white ring with an outer hairline and the soft shadow. The stack names the size;
/// the picture covers it from the top left, aspect kept — width-exact while the page is
/// tall enough, and only the overflow is cropped away.
///
/// A `namespace` wires the card into the page ↔ card transition: both geometry effects
/// are keyed by the tab id, so the reading screen can match against it.
struct TabCard: View {
    let tab: Tab
    var snapshot: Data?
    var size: CGSize
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
                .frame(width: size.width, height: size.height, alignment: .topLeading)
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
        if let image = snapshot.flatMap(UIImage.init(data:)), image.size.width > 0 {
            // The card is the page shrunk: the picture covers it from the top left, aspect
            // kept — width-exact while the page is tall enough, and a page shorter than
            // the card's own aspect fills the height and crops past its sides.
            let covered = Self.coverSize(of: image, in: size)
            Image(uiImage: image)
                .resizable()
                .frame(width: covered.width, height: covered.height)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("tabs.card.snapshot")
        } else {
            placeholder
        }
    }

    /// The picture's size in the card: the larger of the two fit scales, so no card
    /// background shows behind a page shorter than the viewport it was captured at.
    private static func coverSize(of image: UIImage, in card: CGSize) -> CGSize {
        let scale = max(card.width / image.size.width, card.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
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
    TabCard(
        tab: Tab(title: "The web, read slowly", lastActive: .now),
        snapshot: snapshot,
        size: CGSize(width: 240, height: 500)
    )
    .padding(40)
}

#Preview("Placeholder") {
    TabCard(
        tab: Tab(url: URL(string: "https://en.wikipedia.org/wiki/Carbon_steel"), lastActive: .now),
        size: CGSize(width: 240, height: 500)
    )
    .padding(40)
}
