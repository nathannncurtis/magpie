import SwiftUI
import UIKit

/// A list row on the mist: a 26 pt favicon, a two-line block, and a trailing time.
///
/// Rows sit directly on the mist; the separator between rows is drawn by the row above
/// its follower, inset to the text.
struct ListRow: View {
    let title: String
    let subtitle: String
    let host: String?
    var faviconData: Data? = nil
    var time: String? = nil

    private enum RowMetrics {
        static let favicon: CGFloat = 26
        static let faviconGap: CGFloat = 12
        static let verticalPadding: CGFloat = 8
    }

    var body: some View {
        HStack(spacing: RowMetrics.faviconGap) {
            ListFavicon(host: host, data: faviconData, size: RowMetrics.favicon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: RowMetrics.faviconGap)
            if let time {
                Text(time)
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, RowMetrics.verticalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// The row's favicon: the site's own icon when one has been fetched, and otherwise a
/// tile with the host's initial on a hue the host picks for itself.
struct ListFavicon: View {
    let host: String?
    var data: Data? = nil
    var size: CGFloat

    var body: some View {
        Group {
            if let image = data.flatMap(UIImage.init(data:)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                HostTile(host: host, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Self.faviconRadius(size), style: .continuous))
    }

    /// The favicon radii from the foundations spec, by the tile's size.
    static func faviconRadius(_ size: CGFloat) -> CGFloat {
        switch size {
        case 26...: Metrics.Radius.faviconLarge
        case 19...21: Metrics.Radius.faviconMedium
        case 17...18: 5
        default: Metrics.Radius.faviconSmall
        }
    }
}

/// A stand-in tile while no favicon has been fetched, keyed to the host so a page keeps
/// its colour across launches.
struct HostTile: View {
    let host: String?
    var size: CGFloat

    private var radius: CGFloat {
        ListFavicon.faviconRadius(size)
    }

    private var hue: Double {
        guard let host else { return 0.52 }
        var hash = 5381
        for scalar in host.unicodeScalars {
            hash = (hash << 5) &+ hash &+ Int(scalar.value)
        }
        return Double(UInt(bitPattern: hash) % 360) / 360
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
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

#Preview("A row with a time") {
    ListRow(
        title: "How to season a carbon steel pan", subtitle: "seriouseats.com",
        host: "seriouseats.com", time: "9:14 PM"
    )
    .padding(.horizontal, 16)
}

#Preview("A row without a time") {
    ListRow(
        title: "The web, read slowly", subtitle: "quietweb.org · Reading",
        host: "quietweb.org"
    )
    .padding(.horizontal, 16)
}
