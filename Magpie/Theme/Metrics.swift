import CoreGraphics

/// Spacing, radii and bar sizes, in points.
enum Metrics {

    /// Spacing. The base unit is 4 pt.
    enum Spacing {
        /// The base unit.
        static let unit: CGFloat = 4
        /// Floating controls: bars, pills, sheets' inner groups.
        static let insetFloating: CGFloat = 14
        /// The reading bar's sides.
        static let insetReadingBar: CGFloat = 12
        /// List content.
        static let insetList: CGFloat = 16
        /// Running text (Skim). The band runs 20-22.
        static let insetText: CGFloat = 22
        /// Running text at the narrow end of the 20-22 band (onboarding).
        static let insetTextNarrow: CGFloat = 20
        /// Where a bar's bottom edge sits above the screen bottom, home indicator included: at
        /// least `barBottomEdgeMin`, rising with the bottom safe area less
        /// `bottomSafeAreaAllowance` so the bar keeps clear of it on tall-inset devices.
        static func barBottomEdge(safeAreaBottom: CGFloat) -> CGFloat {
            max(barBottomEdgeMin, safeAreaBottom - bottomSafeAreaAllowance)
        }
        /// The least a bar's bottom edge sits above the screen bottom.
        static let barBottomEdgeMin: CGFloat = 26
        /// How much of the bottom safe area the bar is allowed to eat into.
        private static let bottomSafeAreaAllowance: CGFloat = 8
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

    /// How faint a disabled control sits: still there, not calling, still legible.
    static let disabledOpacity = 0.45

    /// The least a control measures, so a tap never lands on less.
    static let tapTarget: CGFloat = 44

    /// Corner radii, all in the continuous (squircle) style.
    enum Radius {
        /// Sheet top corners, matching the device corners.
        static let sheetTop: CGFloat = 38
        /// Grouped boxes: menu groups, settings groups, mod cards.
        static let boxGrouped: CGFloat = 20
        /// Text fields set on a screen's surface.
        static let field: CGFloat = 14
        /// Chips and answer tiles.
        static let chip: CGFloat = 12
        /// Small tiles: an engine's favicon tile, a skeleton bar.
        static let tile: CGFloat = 8
        /// Tags and badges.
        static let badge: CGFloat = 6
        /// Engine tiles, at the upper end of the 18-20 tile band.
        static let engineTile: CGFloat = 20
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
        /// The one height every floating bar and bottom row shares at the default type
        /// size; each grows with Dynamic Type from here.
        static let height: CGFloat = 54
        /// The widest a floating bar grows. Past it (a foldable's open inner screen, an
        /// iPad) the bar stays this wide and sits centred, never edge to edge.
        static let maxWidth: CGFloat = 560
        /// The reading bar in its full state.
        static let readingHeight: CGFloat = height
        /// The reading bar collapsed to its slim pill.
        static let readingSlimHeight: CGFloat = 38
        /// The Skim query bar.
        static let skimQueryHeight: CGFloat = 42
        /// The Skim control bar.
        static let skimControlHeight: CGFloat = height
        /// The bottom search pill on Archive and Bookmarks.
        static let bottomSearchPillHeight: CGFloat = height
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

    /// The menu sheet.
    enum Menu {
        /// The sheet's padding above the grabber.
        static let topPadding: CGFloat = 10
        /// The grabber's width and height.
        static let grabberWidth: CGFloat = 38
        static let grabberHeight: CGFloat = 5
        /// The grabber's gap to the tiles.
        static let grabberGap: CGFloat = 8
        /// A quick-action tile.
        static let tileHeight: CGFloat = 64
        /// A tile's icon.
        static let tileIconSize: CGFloat = 20
        /// A tile's icon-to-label gap.
        static let tileIconGap: CGFloat = 5
        /// The tile row's padding above and below.
        static let tileRowTopPadding: CGFloat = 4
        static let tileRowBottomPadding: CGFloat = 12
        /// The gap between groups.
        static let groupGap: CGFloat = 10
        /// Between the last group and the bar row.
        static let barGap: CGFloat = 14
        /// The bar row's height, and its padding above.
        static let barRowHeight: CGFloat = 48
        static let barRowTopPadding: CGFloat = 6
        /// The bar row's side inset, where its hairline starts.
        static let barRowSideInset: CGFloat = 16
    }
}
