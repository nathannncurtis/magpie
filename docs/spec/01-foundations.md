# 01 · Foundations

Put these values in one `Theme` file: a Swift enum of `Color` / `Font` / `CGFloat` constants. Every colour has a light value and a dark value, and the two switch with the system appearance through an asset catalog colour set or `Color(light:dark:)`.

## Brand colours

| Token | Light | Dark | Use |
|---|---|---|---|
| `ink` | #101115 | #F6F5F1 | Primary filled controls: toggles on, icon squares, primary buttons, Search key, primary Skim pill. Ink and paper **swap** in dark. |
| `onInk` | #F6F5F1 | #101115 | Text and icons on `ink` |
| `paper` | #F6F5F1 | #121316 | Brand paper |
| `sheen` | linear 135°: #0D9488 → #10B981 (55%) → #6EE7B7 | same | The collected thing only (see README) |
| `teal` | #0D7F74 | #5EEAD4 | Text accents: "Get", "Done" on paper screens, the swipe-to-restore background |

## Neutrals

| Token | Light | Dark |
|---|---|---|
| `textPrimary` | #101115 | #F2F2EE |
| `textSecondary` | #5B5D64 | #A3A5AC |
| `textTertiary` | #8A8C93 | #8E9097 |
| `textOnMistSecondary` | #3F4B48 (body) / #4F5A57 (meta) | #A9B9B5 / #93A3A0 |
| `labelOnMist` (uppercase section labels) | #2F5F58 | #7FB5AB |
| `separator` | #101115 @ 7% | #FFFFFF @ 7% |
| `separatorOnMist` | #102824 @ 8% | #FFFFFF @ 7% |
| `card` (solid content cards) | #FFFFFF | #1C1D21 |
| `skimBackground` | #F7F6F2 | #121316 |
| `sheetSolid` (opened search/menu sheet) | #F5F4F0 | #1A1B1F |
| `fill` (ghost buttons, inset tiles) | #101115 @ 6% | #FFFFFF @ 7% |
| `emojiTile` | #EEECE6 | #FFFFFF @ 7% |
| `tag` (engine tag in field) | #F1F0EB | #FFFFFF @ 8% |
| `toggleOff` | #DADAD4 | #FFFFFF @ 16% |
| `pageTintGlass` (default reading-bar tint when the site gives no colour) | #FFF6EE @ 55% | #2C241E @ 55% |
| `warningBackground` / `warningText` / `warningStrong` | #FBEFE6 / #6B3A22 / #4A2412 | #E39272 @ 14% / #F0C3AE / #FFD9C7 |
| `scrim` behind sheets | #101816 @ 18–22% | #000000 @ 32% |

## The mist

The mist is the teal backdrop behind the launch screen, tabs, Skim working, Welcome, the engine picker, Archive, Bookmarks, Settings and Mods. Build it as one `MistBackground` view: a base gradient with four soft radial blobs on top. Positions are fractions of the screen; each radius is given as (w, h) fractions of the screen.

| Layer | Light | Dark |
|---|---|---|
| Base (top → bottom) | #F2F5F2 → #E3ECE8 | #0E1614 → #090D0C |
| Blob 1: center (0.22, 0.12), radius (0.55, 0.38) | #6EE7B7 @ 55% → clear at 70% | #10B981 @ 30% |
| Blob 2: center (0.92, 0.30), radius (0.60, 0.45) | #0D9488 @ 38% → clear at 72% | #0D9488 @ 34% |
| Blob 3: center (0.10, 0.70), radius (0.70, 0.50) | #10B981 @ 28% → clear at 72% | #10B981 @ 16% |
| Blob 4: center (0.85, 0.88), radius (0.80, 0.55) | #0D9488 @ 30% → clear at 75% | #0D9488 @ 26% |

- Use `MeshGradient` or stacked `RadialGradient`s in a `Canvas`.
- **Drifting mist** (Skim working only): two extra blob layers drift slowly in a loop, with periods of 14 s and 18 s, translating ±6%, rotating ±9° and scaling 1.0–1.1, on an ease-in-out curve that alternates direction. Turn it off under Reduce Motion.
- **Fade into page** (Skim no-photo tier): the mist is masked from opaque (0–30%) to 45% (60%) to clear (100%) over its 520 pt height, so it melts into the page. There is never a hard edge.

## Type

**SF Pro** (the system font) for all UI text, with Dynamic Type, and **Fraunces** for display text. There is no IBM Plex Mono and no Instrument Sans in the app; those faces appear only on the boards.

Fraunces: bundle the variable font, weight 600, axes `SOFT 100`, `WONK 0`, opsz automatic. Scale it with `.custom("Fraunces", size:, relativeTo:)`.

| Style | Font | Size / weight | relativeTo | Where |
|---|---|---|---|---|
| `wordmark` | Fraunces | 46 / 600, tracking −0.5 | .largeTitle | Welcome, lowercase "magpie" |
| `screenTitle` | Fraunces | 28–30 / 600 | .largeTitle | Mods, Archive, Bookmarks, Settings headers; onboarding question |
| `skimTitle` | Fraunces | 32 / 600, tracking −0.5, line 1.04 (40 in the no-photo tier) | .largeTitle | Skim page title |
| `skimWorkingTitle` | Fraunces | 28 / 600 | .title | Skim working |
| `sectionTitle` | Fraunces | 17 / 600 | .headline | "Popular this week" |
| `field` | SF Pro | .body (17) | | Search field text |
| `row` | SF Pro | .subheadline (15) regular; titles semibold | | Suggestions, menu rows, list titles |
| `body` | SF Pro | .subheadline (15), line spacing 3 | | Skim sections |
| `meta` | SF Pro | .footnote (13) | | Descriptions, sites, times |
| `small` | SF Pro | .caption (12) | | Subtitles in rows, fine print |
| `label` | SF Pro | .caption2 (11) semibold, uppercase, tracking +0.8 | | "YESTERDAY", "SEARCH", step labels (replaces the Plex Mono labels) |
| `tag` | SF Pro | .caption2 (11) medium, monospacedDigit | | Engine tag, author line ("script · s.okafor") |
| `button` | SF Pro | .body semibold (bar CTAs), .subheadline semibold (pills) | | |

Web pages render in their own fonts. The "reading" board text (Georgia) is page content, not Magpie.

## Spacing

The base unit is 4 pt.

- **Screen side inset:** 14 pt for floating controls (pills, sheets' inner groups, the list search bars); the ReadingBar alone sits at 12, so the page's main control reads a touch wider; 16 pt for list content; 20–22 pt for running text (Skim, onboarding).
- **Bottom controls:** the bar's bottom edge sits 26 pt above the screen bottom; measured from the physical edge, not the safe area. In SwiftUI, lay the bar out in an overlay that ignores the bottom safe area and pad it by `max(26, safeAreaInsets.bottom - 8)`; on home-indicator phones that is 26.
- **Top anchors:** screens measure from the safe-area top, never the physical edge, so nothing rides under a taller status bar. Blocks placed down the screen (the empty list block, Welcome's block) sit at a share of the height on hand, holding their proportion on any height, a short fold screen included; small header gaps stay fixed points.
- **Rows:** suggestion row 46, menu/settings row 50 (46 in Settings), list row 44–48 (favicon 26 + 8 vertical padding).
- **Gaps:** card grid 10, tile grid 8–10, section header above a group 16 top / 7 bottom.

## Radii

All radii use the continuous (squircle) style.

| Element | Radius |
|---|---|
| Reading bar, bottom pills, CTAs | capsule (height/2) |
| Sheets (top corners) | 38, matching the device corners; system sheets give this for free |
| Content cards (mods, featured, folder tiles) | 22–24 |
| Grouped boxes (menu groups, settings groups) | 20 |
| Engine tiles, source cards, preview boxes | 18–20 |
| Search field | 17 (outer ring) / 15.5 (inner) |
| Icon squares (menu, mod icons) | 9 (30 pt) / 12 (44 pt) |
| Favicons | 26 pt → 7, 20 pt → 6, 16 pt → 4 |
| Tab cards in the stack | 26 |

## Shadows

Glass gets its shadow from the system. Solid cards use a soft, wide shadow:
- Light: `y 14, blur 30, spread −18, #102824 @ 35%` plus a hairline `#102824 @ 6%`.
- Dark: `#000 @ 60%` plus a white hairline at 7%.

Never use heavy drop shadows.

## Icons

- Use SF Symbols, weight `.medium`, scale `.medium`, except for the mark and the drawn mod icons.
- Mapping from the board icons:
  - back → `chevron.backward`
  - search → `magnifyingglass`
  - share → `square.and.arrow.up`
  - bookmark → `bookmark`
  - mods → `puzzlepiece.extension`
  - shield → `shield.lefthalf.filled`
  - cookie → custom (no good symbol; draw a 2 pt-stroke cookie)
  - archive → `archivebox`
  - globe → `globe`
  - plus → `plus`
  - check → `checkmark`
  - link → `link`
  - ••• → `ellipsis`
- **Tab count:** a 22 pt rounded square (radius 7) with a 1.8 pt stroke in the current colour, holding the count at 11.5 pt bold. It is not an SF Symbol.

## The mark

The mark is "6d · the cradle": one brushstroke that drops, sweeps under a sheen bead and lifts away dry.

- **Source:** `docs/design/assets/mark-6d.svg`. Export it to a PDF vector asset with Preserve Vector Data.
- **Versions:**
  - `mark.stroke` is the stroke alone, a template image tinted with the current colour.
  - `mark.bead` is the sheen-gradient circle.
  - `mark.tile` is the app icon art: a paper stroke on an ink tile.
- **Drawing it:** for the draw-on animation, reveal the stroke with a trimmed mask path along its centreline: `M170 96 L150 140 C96 250 140 420 300 420 C400 420 440 330 380 286 L330 250` in the 600-unit space, with a 170-unit round-cap stroke, animating `trim(to:)` from 0 to 1. The bead then scales in from 0 with the snap spring (see 05).
- **Small mark** in pills and buttons: 13–20 pt, the stroke only, in the current colour.
