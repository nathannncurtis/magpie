import CoreGraphics

/// Spacing, radii and bar sizes, in points.
enum Metrics {

    /// Spacing. The base unit is 4 pt.
    enum Spacing {
        /// The base unit.
        static let unit: CGFloat = 4
        /// Floating controls: bars, pills, sheets' inner groups.
        static let insetFloating: CGFloat = 14
        /// List content.
        static let insetList: CGFloat = 16
        /// Running text (Skim). The band runs 20-22.
        static let insetText: CGFloat = 22
        /// Running text at the narrow end of the 20-22 band (onboarding).
        static let insetTextNarrow: CGFloat = 20
        /// Bottom padding inside a bottom safe-area inset; with it the bar's bottom edge lands
        /// `barBottomEdge` above the screen bottom.
        static let bottomBarPadding: CGFloat = 8
        /// Where a bar's bottom edge sits above the screen bottom, home indicator included.
        static let barBottomEdge: CGFloat = 26
        /// A suggestion row.
        static let rowSuggestion: CGFloat = 46
        /// A menu row.
        static let rowMenu: CGFloat = 50
        /// A settings row.
        static let rowSettings: CGFloat = 46
        /// A list row. The band runs 44-48; the 26 pt favicon plus vertical padding sets it.
        static let rowList: CGFloat = 46
        /// Card grid gaps.
        static let gapCardGrid: CGFloat = 10
        /// Tile grid gaps. The band runs 8-10.
        static let gapTileGrid: CGFloat = 8
        /// Gap above a section header's group.
        static let gapSectionTop: CGFloat = 16
        /// Gap below a section header, before its group.
        static let gapSectionBottom: CGFloat = 7
    }

    /// Corner radii, all in the continuous (squircle) style.
    enum Radius {
        /// Sheet top corners, matching the device corners.
        static let sheetTop: CGFloat = 38
        /// Content cards: mods, featured, folder tiles. The band runs 22-24.
        static let card: CGFloat = 24
        /// Grouped boxes: menu groups, settings groups.
        static let boxGrouped: CGFloat = 20
        /// Engine tiles, at the upper end of the 18-20 tile band.
        static let tile: CGFloat = 20
        /// Menu tiles, source cards and preview boxes, at the lower end of the 18-20 band.
        static let tileSmall: CGFloat = 18
        /// The search field's outer ring.
        static let searchFieldOuter: CGFloat = 17
        /// The search field's inner field.
        static let searchFieldInner: CGFloat = 15.5
        /// A 44 pt icon square.
        static let iconSquare: CGFloat = 12
        /// A 30 pt icon square.
        static let iconSquareSmall: CGFloat = 9
        /// A 26 pt favicon.
        static let faviconLarge: CGFloat = 7
        /// A 20 pt favicon.
        static let faviconMedium: CGFloat = 6
        /// A 16 pt favicon.
        static let faviconSmall: CGFloat = 4
        /// Tab cards in the stack.
        static let tabCard: CGFloat = 26
    }

    /// Bar heights.
    enum Bar {
        /// The reading bar in its full state.
        static let readingHeight: CGFloat = 60
        /// The reading bar collapsed to its slim pill.
        static let readingSlimHeight: CGFloat = 38
        /// The Skim query bar.
        static let skimQueryHeight: CGFloat = 42
        /// The Skim control bar.
        static let skimControlHeight: CGFloat = 56
        /// The bottom search pill on Archive and Bookmarks.
        static let bottomSearchPillHeight: CGFloat = 54
        /// The "Install from URL" footer pill.
        static let installFooterHeight: CGFloat = 52
        /// The primary onboarding CTA.
        static let primaryCTAHeight: CGFloat = 54
    }

    /// The mist.
    enum Mist {
        /// The height over which the mist fades into the page on the no-photo tier.
        static let fadeHeight: CGFloat = 520
    }
}
