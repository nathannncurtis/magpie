import SwiftUI

/// A stack of source favicons, overlapping: the pages a Skim page was read from.
///
/// Each tile carries a 2 pt ring in the colour behind it, so the tiles read as one
/// stack; on a row the colour behind is the mist.
struct FaviconStack: View {
    let hosts: [String]
    var size: CGFloat = 18
    /// The ring around each tile, in the colour behind the stack; the mist's
    /// ring when none is given.
    var ring: Color? = nil

    private enum StackMetrics {
        static let overlap: CGFloat = 5
        static let ring: CGFloat = 2
    }

    var body: some View {
        HStack(spacing: -StackMetrics.overlap) {
            ForEach(Array(hosts.enumerated()), id: \.offset) { _, host in
                HostTile(host: host, size: size)
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: ListFavicon.faviconRadius(size) + StackMetrics.ring / 2,
                            style: .continuous
                        )
                        .stroke(ring ?? Palette.faviconRingOnMist, lineWidth: StackMetrics.ring)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityHosts))
    }

    private var accessibilityHosts: String {
        hosts.joined(separator: ", ")
    }
}

#Preview {
    FaviconStack(hosts: ["seriouseats.com", "debuyer.com", "reddit.com"])
        .padding(20)
}
