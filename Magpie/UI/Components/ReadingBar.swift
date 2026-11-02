import SwiftUI
import UIKit

/// The readable foreground over a page-tinted glass tint: the bar picks the one that
/// reads on the tint it took from the page (03 · Chrome).
enum ReadableForeground {

    /// The tint's relative luminance at or above which the warm dark reads.
    private static let lightTintLuminance = 0.5

    static func foreground(for tint: Color, scheme: ColorScheme) -> Color {
        isLight(tint, scheme: scheme) ? Palette.onLightPageTint : Palette.onDarkPageTint
    }

    /// Whether the tint reads as light under the given appearance.
    static func isLight(_ tint: Color, scheme: ColorScheme) -> Bool {
        luminance(tint, scheme: scheme) >= lightTintLuminance
    }

    /// The tint's relative luminance, WCAG-style, as resolved under the appearance. The
    /// tint's own opacity is left out: the glass sits over the page the tint was taken
    /// from, so what shows through it is that same colour, not a fixed material base.
    static func luminance(_ tint: Color, scheme: ColorScheme) -> Double {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        guard let channels = Self.channels(of: UIColor(tint).resolvedColor(with: traits)) else {
            return 0
        }
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(channels.red) + 0.7152 * linear(channels.green)
            + 0.0722 * linear(channels.blue)
    }

    /// One colour's straight sRGB channels, or nil where they can't be read.
    private static func channels(
        of color: UIColor
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return (red, green, blue, alpha)
    }
}

/// The id the bar's and the search sheet's glass shapes share, so one grows into the other
/// as a single piece of glass.
enum ChromeGlassID {
    static let chrome = "chrome"
}

/// The reading bar (03 · Chrome): one glass capsule carrying back, the URL, the tab
/// count and the menu trigger, floating over the page and taking the page's tint.
struct ReadingBar: View {

    /// The host the URL pill shows.
    let host: String
    /// The open-tab count.
    let tabCount: Int
    /// Whether the page can go back.
    let canGoBack: Bool
    /// The slim state (05 · Chrome on scroll).
    var isSlim = false
    /// How far the bar has collapsed, 0 full to 1 slim. The interactive scroll tracking
    /// drives this; without it the bar takes the discrete `isSlim`.
    var collapse: CGFloat?
    /// Whether the page failed to load: the URL pill's warning triangle.
    var showsWarning = false
    /// Whether the page belongs to a private tab.
    var isPrivate = false
    /// The page tint the glass takes.
    var tint = Palette.pageTintGlass
    /// Names the bar's glass shape so a later pass can morph it into the search sheet
    /// and the menu.
    var glassNamespace: Namespace.ID? = nil

    /// Drags on the bar: sideways steps through the tabs, up opens the stack.
    var swipe: BarSwipeHandlers? = nil

    let onBack: () -> Void
    let onAddressTap: () -> Void
    let onTabsTap: () -> Void
    let onMenuTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// The bar's heights follow the type size, as its text does — the pill's host text
    /// is what sets them.
    @ScaledMetric(relativeTo: .subheadline) private var scaledFullHeight = Metrics.Bar.readingHeight
    @ScaledMetric(relativeTo: .subheadline) private var scaledSlimHeight = Metrics.Bar.readingSlimHeight
    /// The heights grow with the type size and never drop below the board's at the
    /// smaller sizes.
    private var fullHeight: CGFloat { max(Metrics.Bar.readingHeight, scaledFullHeight) }
    private var slimHeight: CGFloat { max(Metrics.Bar.readingSlimHeight, scaledSlimHeight) }

    /// How much further in from the screen sides the slim pill sits, past the full bar's
    /// inset (the motion board's 110, minus the 12 it already has).
    private static let slimSideInsetGain: CGFloat = 98

    private var progress: CGFloat {
        min(1, max(0, collapse ?? (isSlim ? 1 : 0)))
    }

    private var height: CGFloat {
        fullHeight - (fullHeight - slimHeight) * progress
    }

    private var sideInset: CGFloat {
        Metrics.Spacing.insetReadingBar + Self.slimSideInsetGain * progress
    }

    /// The tabs button's spoken label: the count said with it.
    private var tabsLabel: String {
        String(localized: "Tabs, \(tabCount) open")
    }

    var body: some View {
        namedGlass
            .padding(.horizontal, sideInset)
            .frame(maxWidth: .infinity)
            // The bar grows with the type size to a deliberate stop: past the first
            // accessibility size it would stop being a bar.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// The capsule, named for morphing when a namespace is given.
    @ViewBuilder
    private var namedGlass: some View {
        if let glassNamespace {
            capsule.glassEffectID(ChromeGlassID.chrome, in: glassNamespace)
        } else {
            capsule
        }
    }

    private var capsule: some View {
        HStack(spacing: 0) {
            side {
                CircleButton(systemName: "chevron.backward", action: onBack)
                    .disabled(!canGoBack)
                    .accessibilityLabel(Text("Back"))
                    .accessibilityIdentifier("bar.back")
            }
            URLPill(
                host: host, collapse: progress, showsWarning: showsWarning, isPrivate: isPrivate,
                action: onAddressTap
            )
            .accessibilityIdentifier("bar.url")
            side {
                CircleButton(action: onTabsTap) { TabCount(count: tabCount) }
                    .accessibilityLabel(Text(tabsLabel))
                    .accessibilityIdentifier("bar.tabs")
            }
            side {
                CircleButton(systemName: "ellipsis", action: onMenuTap)
                    .accessibilityLabel(Text("Menu"))
                    .accessibilityIdentifier("bar.menu")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 5)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .foregroundStyle(ReadableForeground.foreground(for: tint, scheme: colorScheme))
        .contentShape(.capsule)
        .modifier(BarSwipeGesture(handlers: swipe))
        .glassEffect(.regular.tint(tint), in: .capsule)
    }

    /// Wraps a side button: it fades as the bar slims, and its slot folds away only
    /// once the button has stopped taking taps — the tap target never shrinks under a
    /// finger mid-collapse. The folding slot clips the visuals alone.
    private func side<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: CircleButtonLayout.hitSize)
            .opacity(1 - progress)
            .frame(width: CircleButtonLayout.hitSize * (1 - fold))
            .clipped()
            .allowsHitTesting(progress < 0.5)
    }

    /// How far the button's slot has folded, 0 to 1: the hit frame holds at full width
    /// while the button can still take a tap, then the slot folds to nothing.
    private var fold: CGFloat {
        progress < 0.5 ? 0 : (progress - 0.5) * 2
    }
}

#Preview("Full") {
    ReadingBar(
        host: "quietweb.org",
        tabCount: 4,
        canGoBack: true,
        tint: Palette.pageTintGlass,
        onBack: {},
        onAddressTap: {},
        onTabsTap: {},
        onMenuTap: {}
    )
    .padding(.vertical, 20)
}

#Preview("Slim") {
    ReadingBar(
        host: "quietweb.org",
        tabCount: 4,
        canGoBack: true,
        isSlim: true,
        tint: Palette.pageTintGlass,
        onBack: {},
        onAddressTap: {},
        onTabsTap: {},
        onMenuTap: {}
    )
    .padding(.vertical, 20)
}
