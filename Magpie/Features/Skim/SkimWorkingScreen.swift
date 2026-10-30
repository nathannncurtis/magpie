import SwiftUI

/// 08 · Skim working: the drifting mist, the mark drawing itself at 96 pt, the
/// query fading in under it, the three source favicons filling one by one, and
/// Cancel. Nothing else.
struct SkimWorkingScreen: View {

    let query: String
    let progress: SkimProgress
    let onCancel: () -> Void
    /// The run has just finished: the mark scales down and fades, and the mist
    /// clears into the page behind (05 · 04).
    var exiting = false

    private enum Layout {
        static let markSize: CGFloat = 96
        /// Where the mark sits from the top of the screen.
        static let markTop: CGFloat = 290
        static let titleGap: CGFloat = 18
        static let statusGap: CGFloat = 14
        static let statusInnerGap: CGFloat = 9
        static let favicon: CGFloat = 18
        static let faviconGap: CGFloat = 5
        static let faviconRing: CGFloat = 2
        /// An unread favicon, held back until its page lands.
        static let dimmed: Double = 0.35
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleArrived = false
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        ZStack {
            MistBackground(drifting: true)
                .ignoresSafeArea()
                .opacity(exiting ? 0 : 1)
            VStack(spacing: 0) {
                Color.clear.frame(height: Layout.markTop)
                MarkSpinner(size: Layout.markSize)
                    .foregroundStyle(Palette.textPrimary)
                    .scaleEffect(exiting && !reduceMotion ? 0.7 : 1)
                    .opacity(exiting ? 0 : 1)
                Color.clear.frame(height: Layout.titleGap)
                Text(displayQuery)
                    .font(Typography.skimWorkingTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Metrics.Spacing.insetText)
                    .opacity(titleArrived && !exiting ? 1 : 0)
                Color.clear.frame(height: Layout.statusGap)
                status
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
            VStack {
                Spacer()
                cancel
            }
            .padding(.horizontal, Metrics.Spacing.insetFloating)
            .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset))
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { arrive() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("skim.working")
    }

    /// The three favicons filling in as each page is read, with the reading line.
    private var status: some View {
        HStack(spacing: Layout.statusInnerGap) {
            HStack(spacing: Layout.faviconGap) {
                ForEach(
                    Array(progress.plannedHosts.prefix(SkimPage.initialSourceCount).enumerated()),
                    id: \.offset
                ) { index, host in
                    ListFavicon(host: host, size: Layout.favicon)
                        .overlay(
                            RoundedRectangle(
                                cornerRadius:
                                    ListFavicon.faviconRadius(Layout.favicon)
                                    + Layout.faviconRing / 2,
                                style: .continuous
                            )
                            .stroke(Palette.faviconRingOnMist, lineWidth: Layout.faviconRing)
                        )
                        .opacity(index < progress.readCount ? 1 : Layout.dimmed)
                }
            }
            Text("Reading \(progress.plannedCount) pages")
                .font(Typography.small)
                .fontWeight(.medium)
                .foregroundStyle(Palette.skimStatus)
        }
        .accessibilityElement(children: .combine)
    }

    private var cancel: some View {
        Button(action: onCancel) {
            Text("Cancel")
                .font(Typography.buttonBar)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.Bar.skimControlHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("skim.cancel")
    }

    /// The query as the board writes it: the first letter up, the rest as typed.
    private var displayQuery: String {
        query.prefix(1).uppercased() + query.dropFirst()
    }

    private func arrive() {
        guard !titleArrived else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.5).delay(0.4)) {
            titleArrived = true
        }
    }
}

#Preview {
    SkimWorkingScreen(
        query: "seasoning carbon steel",
        progress: SkimProgress(
            plannedHosts: ["seriouseats.com", "debuyer.com", "reddit.com"], readCount: 2),
        onCancel: {})
}
