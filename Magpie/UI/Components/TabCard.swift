import SwiftUI
import UIKit

/// One card in the tab stack: the page snapshot at 62% of the screen's scale, in a
/// 5 pt white ring with an outer hairline and the soft shadow. The stack names the size;
/// the picture sits at the card's exact width, aspect kept, from the top — the whole
/// page width shows, its depth crops away, and a page shorter than the card runs on in
/// its own colour below the picture.
///
/// A `namespace` wires the card into the page ↔ card transition: both geometry effects
/// are keyed by the tab id, so the reading screen can match against it.
struct TabCard: View {
    let tab: Tab
    var snapshot: Data?
    /// The page's own sampled background, for the space below a short page's picture.
    var pageBackground: Color? = nil
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
                .frame(width: size.width, height: size.height, alignment: .top)
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
            // The card is the page shrunk: the picture at the card's exact width, aspect
            // kept, from the top; below it the page's own colour, so a short page reads
            // as the page continuing rather than a gap.
            ZStack(alignment: .top) {
                Rectangle().fill(continuation(of: image))
                Image(uiImage: image)
                    .resizable()
                    .frame(
                        width: size.width,
                        height: size.width * image.size.height / image.size.width
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("tabs.card.snapshot")
            }
            .onAppear { Self.logFit(tab: tab, image: image, card: size) }
        } else {
            placeholder
        }
    }

    /// The cards whose picture numbers have been logged, once each.
    @MainActor private static var loggedFits: Set<Tab.ID> = []

    /// The picture's numbers against the card's, once per card — the width-fit is being
    /// diagnosed on the simulator.
    @MainActor private static func logFit(tab: Tab, image: UIImage, card: CGSize) {
        guard !loggedFits.contains(tab.id) else { return }
        loggedFits.insert(tab.id)
        let frame = CGSize(
            width: card.width,
            height: card.width * image.size.height / image.size.width)
        SnapshotLog.event(
            "card tab=\(tab.id.uuidString.prefix(4))"
                + " image=\(Int(image.size.width))x\(Int(image.size.height))@\(image.scale)"
                + " card=\(Int(card.width))x\(Int(card.height))"
                + " frame=\(Int(frame.width))x\(Int(frame.height))")
    }

    /// What the card shows where the picture stops: the page's sampled colour, else the
    /// snapshot's own last row, else the card colour.
    private func continuation(of image: UIImage) -> Color {
        pageBackground ?? Self.lastRowColour(of: image) ?? Palette.card
    }

    /// The snapshot's own colour at its very bottom, so a short page runs on as itself.
    private static func lastRowColour(of image: UIImage) -> Color? {
        guard let cg = image.cgImage else { return nil }
        let row = CGRect(x: 0, y: cg.height - 1, width: cg.width, height: 1)
        guard
            let strip = cg.cropping(to: row),
            let context = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else { return nil }
        let pixel = data.assumingMemoryBound(to: UInt8.self)
        guard pixel[3] > 0 else { return nil }
        return Color(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255)
    }

    /// What the card shows until the first snapshot lands.
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.Radius.tabCard, style: .continuous)
                .fill(Palette.card)
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                if let host = tab.host {
                    Text(host)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.textSecondary)
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
    // A page shorter than its card: the picture, then the page running on below it.
    let snapshot = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 360)).pngData { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(origin: .zero, size: CGSize(width: 240, height: 360)))
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
