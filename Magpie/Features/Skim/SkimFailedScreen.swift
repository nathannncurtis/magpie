import SwiftUI

/// 16 · Skim couldn't finish: the working scene with the mark standing still at
/// 55%, the query above and the title below it, one line saying why, then the
/// results on the engine or a fresh attempt. Nothing is half-built.
struct SkimFailedScreen: View {

    let query: String
    let line: String
    let onShowResults: () -> Void
    let onRetry: () -> Void

    private enum Layout {
        static let markSize: CGFloat = 96
        static let queryTop: CGFloat = 62
        static let queryLineHeight: CGFloat = 16
        static let markTop: CGFloat = 290
        static let stillMark: Double = 0.55
        static let titleGap: CGFloat = 18
        static let lineGap: CGFloat = 14
        static let lineInset: CGFloat = 40
        static let footerGap: CGFloat = 12
        static let ctaHeight = Metrics.Bar.primaryCTAHeight
    }

    @State private var bottomInset: CGFloat = 0

    var body: some View {
        ZStack {
            MistBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Color.clear.frame(height: Layout.queryTop)
                Text(query)
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                Color.clear.frame(
                    height: Layout.markTop - Layout.queryTop - Layout.queryLineHeight)
                Mark(size: Layout.markSize)
                    .foregroundStyle(Palette.textPrimary)
                    .opacity(Layout.stillMark)
                Color.clear.frame(height: Layout.titleGap)
                Text(displayQuery)
                    .font(Typography.skimWorkingTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Metrics.Spacing.insetText)
                Color.clear.frame(height: Layout.lineGap)
                Text(line)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, Layout.lineInset)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
            VStack {
                Spacer()
                footer
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
        .accessibilityIdentifier("skim.failed")
    }

    /// The results on the engine, then a second try.
    private var footer: some View {
        VStack(spacing: Layout.footerGap) {
            Button(action: onShowResults) {
                Text("Show search results")
                    .font(Typography.buttonBar)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.ctaHeight)
                    .contentShape(.capsule)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.ink)
            .accessibilityIdentifier("skim.showResults")

            Button(String(localized: "Try again"), action: onRetry)
                .font(Typography.row)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
                .padding(6)
                .accessibilityIdentifier("skim.retry")
        }
    }

    /// The query above the mark is as typed; the title under it opens with a
    /// capital, the way the working screen writes it.
    private var displayQuery: String {
        query.prefix(1).uppercased() + query.dropFirst()
    }
}

#Preview {
    SkimFailedScreen(
        query: "seasoning carbon steel",
        line: String(
            localized: "Only \(1) of \(3) pages could be read. That's not enough to Skim."),
        onShowResults: {},
        onRetry: {})
}
