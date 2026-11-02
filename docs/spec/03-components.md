# 03 · Components

Each component is one SwiftUI view in `UI/Components/`. Sizes are in points. "Dark" lists only what changes.

## Chrome

**ReadingBar**
- Glass capsule, 60 tall; inset 12 from the screen sides and 26 above the bottom edge (see 01 Spacing). Padding: 4 on the leading side, 5 on the trailing side. The 60/38 heights scale with Dynamic Type, capped at the first accessibility size.
- Contents, left to right:
  - `CircleButton(back)`
  - `URLPill`, which grows to fill
  - `CircleButton(TabCount)`
  - `CircleButton(ellipsis)`
- Icon colour: the page tint's readable foreground. The default is #3A2E26 on the warm tint, and the dark default is #F2F2EE.
- **States:** full; **slim** while scrolling (05 · Chrome on scroll); **••• pressed**, which fills that button with `ink` at 8–10% while the menu is open.

**CircleButton**: a 48 × 48 hit area (minimum 44) holding a 20 pt symbol, with no background of its own. A disabled button keeps its place and its hit area, at 45% opacity.

**URLPill**: shows the host only ("quietweb.org"), in `row` medium, centred. It is 48 tall in the full bar and 30 in the slim bar, and its tap target never drops below 44 tall. A warning triangle (`exclamationmark.triangle.fill`) appears only on errors; HTTPS is assumed, so no lock ever shows. Tapping it opens search.

**TabCount**: see 01 Icons. It shows the open-tab count. Above 99 it shows "∞".

## Search

**SearchSheet**: from top to bottom:
- `SearchField`, inset 14 from the sheet's sides
- up to 3 `SuggestionRow`s, with 6 pt padding around the list
- the system keyboard

The sheet's top corners are 38. On the mist it is glass; opened from a page, it becomes solid (02). Its top padding is 14.

**SearchField**
- **Ring:** an outer 1.5 pt `sheen` ring with radius 17.
- **Inner field:** 48 tall at the default size, growing with Dynamic Type; radius 15.5, filled white at 72% (dark: #1D2023). Padding: 16 leading, 8 trailing.
- **Contents:**
  - the text field, in `field`, with autocorrect ON
  - an `EngineTag` at the trailing end: the engine name in `tag`, `textSecondary` on the `tag` fill, radius 9, padding 6 × 8
- **Keyboard:** return key reads "Search", with an `ink` background (paper in dark). This is a styled toolbar key only if iOS allows it; otherwise use the system Search key.

**SuggestionRow**
- 46 tall, horizontal padding 12, gap 12.
- Contents: a `magnifyingglass` icon at 16 in `textTertiary`, then the suggestion in `row`, then a trailing `SkimPill`.
- Tapping the row searches; tapping the pill runs Skim for that query.
- VoiceOver reads the row as the query alone, with a named "Skim" action in place of the pill.

**SkimPill**
- Capsule; padding 6 × 11; text `small` semibold reading "Skim", with a 13 pt mark.
- Its tap target is a 44 pt band centred on the capsule, filling the row's height.
- **Resting:** white at 45%, a 1 pt `ink` 16% border, and a white inner top highlight. Dark: white at 7% with a white 18% border.
- **Primed** (the first row, top suggestion only): solid `ink` with `onInk` text.
- Hidden entirely when Skim is unavailable or turned off.

## Menu

**MenuSheet**: the bar grows into it (05). From top to bottom:
- a `Grabber`: 38 × 5, radius 3, `ink` at 18%
- a `MenuTileRow`
- `MenuGroup`s
- the ReadingBar, pinned at the base

The sheet **hugs its content**: 14 pt between the last group and the bar, never more.

**MenuTileRow**: 4 equal tiles with gap 8 and padding 4 × 14 × 12. Each tile:
- at least 64 tall, radius 18; a long label wraps to a second line instead of clipping
- fill: white at 50% with a white inner hairline (dark: white at 6%)
- content: a 20 pt icon over a label in caption semibold
- tiles: Skim (the mark), Bookmark (tap saves, long-press opens Bookmarks), Share, Mods

**MenuGroup**
- Inset 14 from the sides, radius 20, filled white at 55% (dark: white at 6%).
- Rows are `MenuRow`s with `separator` lines between them.

**MenuRow**
- 50 tall, padding 14, gap 12.
- Contents: an `IconSquare`, then the label in `row`, then at the trailing end either a `Toggle` or a value plus chevron (`textSecondary`).
- Rows, as on the board:
  - Block ads & trackers [toggle]
  - Block cookie banners [toggle]
  - Archive inactive tabs [After 1 day] — the whole row opens the interval picker
  - Search engine [DuckDuckGo ›]
  - Skim for me [toggle]
  - Settings [›], added 2026-10-30; this row isn't on the board yet

**IconSquare**: 30 × 30, radius 9, `ink` fill with a `onInk` 16 pt icon. Dark: paper fill with ink icon.

**Toggle**: the system `Toggle` tinted `toggleOn` — `ink` in light, `teal` in dark, where the system knob's white would vanish on the near-white ink track. The whole row flips the switch, not just the knob.

## Tabs

**TabCard**
- A live snapshot of the page, radius 26, at 62% of the screen scale.
- Ring: 5 pt of white at 38%, plus a 0.75 pt outer hairline of white at 75%, plus the soft shadow. Dark: white at 6% and 16%.
- Above each card: a `TabLabel` (16 pt favicon plus the title in caption semibold, one line, truncated).
- VoiceOver: the card speaks as one element (title, host, button, with a Close Tab action); the face inside is a single named element — the picture the UI tests wait on — never a bare second stop.
- Gestures:
  - fling up to close (see 05)
  - tap to open

**TabStack**: cards sit side by side on the mist, 14 pt apart, with the current card centred and its neighbours peeking in from the screen edges.
- Bottom row, inset 16 from the sides and 34 above the bottom: `ArchivedChip` ("Archived · 12") on the left, the count ("3 open", `small`, `labelOnMist`) in the middle, and `PlusButton` on the right.

**ArchivedChip**: glass capsule, at least 46 tall (growing with Dynamic Type), padding 0 × 16, with an `archivebox` icon and the label in `row` semibold.

**PlusButton**: 54 × 54 ink glass circle (paper in dark) with a 22 pt plus.

## Skim

**SkimQueryBar**
- Glass capsule, 42 tall, inset 14 from the sides, 4 pt below the status bar's bottom edge (58 pt from the top on the board's phone), so it sits just under the status bar on any device.
- Contents: a search icon, the query, then a trailing tag of the mark plus "Skim" in caption semibold.
- Tapping it edits the query. The capsule carries an invisible 44 pt target: a taller frame around the 42 pt glass.

**PhotoHeader**: chosen by how many photos were found.
- **3 or more → mosaic.** 300 tall; a 1.55 : 1 grid with a 3 pt gap. The large photo sits on the left; the right column stacks two.
- **1 → hero.** One photo, 300 tall.
- **0 → no photos.** The `MistBackground` fades into the page (01 Mist); the title moves up at 40 pt.

Photos come only from the source pages' `og:image` or largest article image. There is never an image search.

**SkimHeader**
- The title in `skimTitle` (padding 18 × 22 × 4).
- Below it, a `FaviconStack`, then "From 3 pages · read on this phone" in `small` medium `textSecondary`.

**FaviconStack**: 20 pt favicons, radius 6, overlapping by −5, each with a 2 pt ring in the page background colour.

**SkimSection**: a two-column grid, 30 and the remaining width, with gap 10, padding 0 × 22 and 14 above.
- **Left column:** an `EmojiTile` (30 × 30, radius 9, `emojiTile` fill, 16 pt emoji).
- **Right column:** the **Term** in `body` semibold `textPrimary`, then " — ", then the claim in `body`, then one or more inline citation digits.

**Citation digits**: inside a claim the digits are the circled-digit glyphs (1–10; anything higher in brackets), links a finger follows while reading rather than buttons it aims at, so they carry no 44 pt target of their own — the source card itself is the target. They take `teal` in light (the sheen's green falls short of contrast on the skim paper) and the sheen's mid green in dark, and scale with Dynamic Type beside the claim's `body` text. Tapping one scrolls to its source card.

**CitationBadge**: the 17 pt `sheen` circle with the source number in `onSheen`, 10 pt semibold, on a source card's site line.

**SourceCard**: solid card, 200 wide, radius 18, padding 8.
- Contents: a thumbnail (84 tall, radius 12), then the site line (favicon, `CitationBadge` and host in `tag`), then the title in `meta` semibold.
- Cards sit in a horizontal row under a "Sources" heading.

**SkimControlBar**
- Glass capsule, 56 tall, inset 14 from the sides and 26 above the bottom (see 01 Spacing).
- Contents, left to right:
  - "Dig deeper · up to 10", with the mark, in `row` semibold
  - a divider: 1 × 24, `ink` at 14%
  - a share `CircleButton`, 46
- "Dig deeper" reads more sources, up to 10 in total. It is hidden once 10 have been read.

**MarkSpinner**: the mark's draw-on animation (01 The mark), looping. It is used on Skim working (96 pt) and in the Install button (24 pt).

## Lists (Archive, Bookmarks)

**ListRow**
- Padding 8 × 0.
- Contents: a 26 pt favicon (radius 7), then a two-line block (the title in `row` semibold, one line; the subtitle in `small` `textOnMistSecondary`), then a trailing time in `small`.
- Rows sit directly on the mist. Separators are `separatorOnMist`, inset to the text.

**ScreenHeader**: the head of every secondary screen (Archive, Bookmarks, Mods, Settings and its pages, the Skim page and Skim failed).
- A 36 pt control row, sides `insetList`: a leading slot (Back chevron, Edit/Save, or empty) and a trailing slot (Done, or empty). Every control is a 44 pt target (`Metrics.tapTarget`) that spills 4 pt past the row, and every Done, Edit, Save and Back label is `buttonPill`.
- Under the row, the title in `screenTitle`, 2 pt below it, 10 pt above what follows, `insetList` at the sides, inside `readableWidth()`. It sits at the same height on every screen. The Skim screens carry the row alone, with Done on a glass capsule over the page.
- Done leaves the screen, as the back swipe does.

**SectionLabel**: the `label` style in `labelOnMist`, at the `insetList` inset: "YESTERDAY", "EARLIER THIS WEEK", "SEARCH". The one section label on every list screen.

**GroupedBox**: inset 16 from the sides, radius 20, `.regularMaterial` with a 0.75 pt hairline (`groupedSurface()`). Settings groups, the default-browser card, the featured mod card and the mod cards wear it. Archive and Bookmarks stay as flat rows on the mist. A flat row's divider is inset by the same amount at both ends.

**RowSeparator**: the 0.5 pt `separatorOnMist` hairline between flat rows.

**Icons**: inline symbols take `Typography.icon(.small | .regular | .large)`: 15, 18 and 22 pt, medium weight, scaling with Dynamic Type.

**PrimaryButtonStyle**: the one primary action, an `ink` capsule with an `onInk` label (paper in dark), pressed to 0.97. Sizes: `bar` (54 tall, full width, `buttonBar`), `sheet` (50 tall, `buttonPill`) and `compact` (hugs its label, 44 pt target). Disabled, the fill drops to `fill` and the label to `textSecondary`, which keeps 4.5:1; it never fades out. Used by Get, Install, Continue and Show search results.

**FolderRow**: a 28 pt `ink` tile (radius 9) holding a `folder` line icon in `onInk`, then the name, the count and a chevron. The row is at least 44 tall. The tile is the same ink tile the Settings rows and mod icons wear; folders no longer carry their own colours.

**SkimPageRow**: like ListRow, but the leading 26 pt tile is the mark on `ink` (radius 7) and the trailing element is a `FaviconStack` of its sources at 18 pt. The subtitle reads "Skim page · Kitchen".

**BottomSearchPill**
- Glass capsule, at least 54 tall (growing with Dynamic Type), inset 14 from the sides and 26 above the bottom (see 01 Spacing).
- Contents: a search icon and the placeholder in `row` `textOnMistSecondary`.
- Focused, it lifts itself clear of the keyboard, keeping its 26 pt foot clearance above the keys.
- The list behind it uses the soft scroll-edge effect.

## Mods

**SegmentedControl**: glass capsule, 38 tall, inset 3 inside the capsule. Segments: "Directory" and "Installed · N". The selected segment is solid `card` with a small shadow (dark: white at 16%). Each segment's tap target is at least 44 tall, standing taller than the track itself.

**FeaturedModCard**: a `GroupedBox`-surface card, radius 20.
- On top, a 150 pt preview showing what the mod does. For Google Answer Box, this is the drawn mini Google result with the answer card ringed.
- Below the preview, a `ModMeta` row.

**ModRow**: a grid of 44, the remaining width and an auto column, with gap 12 and padding 11 × 0.
- Contents:
  - a `ModIcon` (44, radius 12, an `onInk` glyph on an `ink` tile)
  - the name in `row` semibold
  - the description in `meta` `textSecondary`
  - the author line in `tag` `textTertiary` ("script · s.okafor")
  - a trailing `GetButton` or `InstalledCheck`
- Rows are grouped in a `GroupedBox` (radius 20), hairlines between them.

**GetButton**: the compact primary button, reading "Get" in `buttonPill` `onInk` on `ink`, padding 6 × 16. The capsule carries an invisible 44 pt target.

**InstalledCheck**: a 30 pt `sheen` circle with an `onSheen` checkmark. It pops with the snap spring (05) when an install lands — on a directory row or the featured card — and stays still on a revisit.

**InstallFooter**: a glass capsule pill, 52 tall, reading "Install from URL" with a link icon.

**InstallSheet**: see 04 · Screen 12.

## Onboarding

**EngineTile**
- Glass, 92 tall, radius 20, padding 12 × 14.
- Contents: the real favicon (30 pt, radius 8) at top left; the name in `row` semibold and a one-line note in `small` at the bottom (wrapping when type grows).
- **Selected:** a 2 pt `ink` ring, a 22 pt `ink` check badge at top right, and a more opaque fill.
- **Other tile:** no glass, just a 1 pt `ink` 14% outline and a generic icon on a `fill` square.

**PrimaryCTA**: the primary button in its `bar` size: 54 tall, full width minus 32, with semibold text that scales with Dynamic Type. In dark it is paper. Disabled, it reads in the quiet fill, not faded.

## Settings

**Settings groups**: a `GroupedBox`. Its rows are `MenuRow`s at 46 tall.

**DefaultBrowserCard**: a card in the `GroupedBox` surface that reads "Make Magpie your default browser" / "Links from other apps open here. Set in iOS Settings." with a trailing ink "Open" capsule.
- The "Open" button calls `UIApplication.openDefaultApplicationsSettingsURLString`.
- The card is shown only until Magpie is the default browser; check with `UIApplication.shared.isDefault(.webBrowser)`, again whenever the app returns to the foreground.
