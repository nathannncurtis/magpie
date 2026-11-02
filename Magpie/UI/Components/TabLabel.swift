import SwiftUI
import UIKit

/// The title riding above a tab card: a 16 pt favicon and the title in caption semibold,
/// one line, truncated.
struct TabLabel: View {
    let title: String
    let host: String?
    let faviconData: Data?
    /// A private tab: the eye with a slash stands where the favicon would.
    var isPrivate = false

    private enum LabelMetrics {
        static let favicon: CGFloat = 16
        static let faviconGap: CGFloat = 7
    }

    var body: some View {
        HStack(spacing: LabelMetrics.faviconGap) {
            favicon
            Text(title)
                .font(Typography.small.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var favicon: some View {
        if isPrivate {
            Image(systemName: "eye.slash")
                .font(.system(size: LabelMetrics.favicon * 0.75, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: LabelMetrics.favicon, height: LabelMetrics.favicon)
                .accessibilityIdentifier("tabs.label.private")
        } else if let image = faviconData.flatMap(UIImage.init(data:)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: LabelMetrics.favicon, height: LabelMetrics.favicon)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.faviconSmall, style: .continuous))
        } else {
            FaviconTile(host: host, size: LabelMetrics.favicon)
        }
    }
}

/// A stand-in tile while no favicon has been fetched: the host's initial on a hue the
/// host picks for itself, so a tab keeps its colour across launches.
private struct FaviconTile: View {
    let host: String?
    let size: CGFloat

    private var hue: Double {
        guard let host else { return 0.52 }
        var hash = 5381
        for scalar in host.unicodeScalars {
            hash = (hash << 5) &+ hash &+ Int(scalar.value)
        }
        return Double(UInt(bitPattern: hash) % 360) / 360
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.Radius.faviconSmall, style: .continuous)
            .fill(Color(hue: hue, saturation: 0.34, brightness: 0.58))
            .frame(width: size, height: size)
            .overlay {
                if let initial = host?.first {
                    Text(String(initial).uppercased())
                        .font(.system(size: size * 0.56, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: size * 0.62, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
    }
}

#Preview("Title") {
    TabLabel(title: "The web, read slowly", host: "quietweb.org", faviconData: nil)
        .padding()
}

#Preview("Falls back to the host") {
    TabLabel(title: "", host: "en.wikipedia.org", faviconData: nil)
        .padding()
}
