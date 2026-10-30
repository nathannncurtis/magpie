import SwiftUI
import UIKit

/// The readable foreground over a page-tinted glass tint: the bar picks the one that
/// reads on the tint it took from the page (03 · Chrome).
enum ReadableForeground {

    /// On a light tint: the warm dark of the spec's default.
    static let onLightTint = Color(hex: 0x3A2E26)
    /// On a dark tint: the off-white of the spec's dark default.
    static let onDarkTint = Color(hex: 0xF2F2EE)

    /// The tint's relative luminance at or above which the warm dark reads.
    private static let lightTintLuminance = 0.5

    static func foreground(for tint: Color, scheme: ColorScheme) -> Color {
        isLight(tint, scheme: scheme) ? onLightTint : onDarkTint
    }

    /// Whether the tint reads as light under the given appearance.
    static func isLight(_ tint: Color, scheme: ColorScheme) -> Bool {
        luminance(tint, scheme: scheme) >= lightTintLuminance
    }

    /// The tint's relative luminance, WCAG-style, as resolved under the appearance.
    static func luminance(_ tint: Color, scheme: ColorScheme) -> Double {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let resolved = UIColor(tint).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
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
    /// Whether the menu is open: the ••• state.
    var isMenuOpen = false
    /// Whether the page failed to load: the URL pill's error lock.
    var showsLock = false
    /// The page tint the glass takes.
    var tint = Palette.pageTintGlass
    /// Names the bar's glass shape so a later pass can morph it into the search sheet
    /// and the menu.
    var glassNamespace: Namespace.ID? = nil

    let onBack: () -> Void
    let onAddressTap: () -> Void
    let onTabsTap: () -> Void
    let onMenuTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// The id the bar's glass shape is known by when morphing.
    private static let glassID = "chrome"
    /// How much further in from the screen sides the slim pill sits, past the full bar's
    /// inset (the motion board's 110, minus the 12 it already has).
    private static let slimSideInsetGain: CGFloat = 98

    private var progress: CGFloat {
        min(1, max(0, collapse ?? (isSlim ? 1 : 0)))
    }

    private var height: CGFloat {
        Metrics.Bar.readingHeight
            - (Metrics.Bar.readingHeight - Metrics.Bar.readingSlimHeight) * progress
    }

    private var sideInset: CGFloat {
        Metrics.Spacing.insetReadingBar + Self.slimSideInsetGain * progress
    }

    var body: some View {
        namedGlass
            .padding(.horizontal, sideInset)
            .frame(maxWidth: .infinity)
    }

    /// The capsule, named for morphing when a namespace is given.
    @ViewBuilder
    private var namedGlass: some View {
        if let glassNamespace {
            capsule.glassEffectID(Self.glassID, in: glassNamespace)
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
            }
            URLPill(host: host, collapse: progress, showsLock: showsLock, action: onAddressTap)
            side {
                CircleButton(action: onTabsTap) { TabCount(count: tabCount) }
                    .accessibilityLabel(Text("Tabs"))
            }
            side {
                CircleButton(systemName: "ellipsis", isPressed: isMenuOpen, action: onMenuTap)
                    .accessibilityLabel(Text("Menu"))
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 5)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .foregroundStyle(ReadableForeground.foreground(for: tint, scheme: colorScheme))
        .glassEffect(.regular.tint(tint), in: .capsule)
    }

    /// Wraps a side button: its width collapses and it fades as the bar slims.
    private func side<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: CircleButtonLayout.hitSize)
            .frame(width: CircleButtonLayout.hitSize * (1 - progress))
            .clipped()
            .opacity(1 - progress)
            .allowsHitTesting(progress < 0.5)
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
