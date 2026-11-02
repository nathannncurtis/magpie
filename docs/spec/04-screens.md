# 04 · Screens

The numbers match the screen board. Every screen exists in light and dark; dark rules are at the end. Component names refer to 03.

## Navigation map

```
Cold start, no tabs ── Launch (01, keyboard up) ──search──▶ Reading (02)
                                     └──Skim pill──▶ Skim working (08) ──▶ Skim page (04)
Reading ──tap URL──▶ Search sheet (01 morph)       Reading ──•••──▶ Menu (05)
Reading ──tab count──▶ Tabs (03) ──Archived chip──▶ Archive (09)
Menu ──Mods tile──▶ Mods (06) ──footer──▶ Install from URL (12)
Menu ──Bookmark tile: tap saves, long-press──▶ Bookmarks (10)      Menu ──Settings ›──▶ Settings (11)
First ever launch ──▶ Welcome (07a) ──▶ Engine picker (07b) ──▶ Launch (01)
```

Later launches restore the last tab, with no animation.

---

## 01 · Launch / search
- **Background:** the mist.
- **Sheet:** a `SearchSheet` attached to the keyboard, glass, edge to edge, top corners 38. The field is focused with the keyboard up on arrival.
- **Suggestions:** up to 3 rows, coming from the chosen engine's suggest API. The first row's Skim pill is primed (ink). The rows stagger in once as the list arrives; typing animates the rows it adds or drops, never resetting the list.
- **Empty field:** show recent searches as rows, or no rows at all. Nothing else.
- **Submitting:** a query goes to the chosen engine; a URL goes to that site. The Skim pill runs Skim (08).
- **Opened from a page:** the bar morphs into this sheet and the sheet turns solid (02, 05 · Open search).
- **Dismissed with no tabs:** a swipe down or a tap away folds the sheet into the mist; there is no stack to go back to, and the screen never goes blank. The mark (sheen, 96) sits in the centre, over a bottom row placed like the tabs row (03): the Archived chip on the left, + in the centre (it brings the sheet back with the keyboard up; a long-press opens a private tab), and a Settings gear on the right.

## 02 · Reading
- **Layout:** a `WKWebView` that starts below the status bar and runs to the bottom edge under the floating `ReadingBar`. The strip above the page, under the status bar, takes the page's own top colour (`themeColor`, else its own background, else paper), so the screen still reads edge to edge.
- **Bar tint:** comes from the page's `themeColor`, or `underPageBackgroundColor` when there's no theme colour.
- **Scrolling:** collapses the bar to slim (05 · Chrome on scroll).
- **Dark mode on pages:** never inverted. Send `Sec-CH-Prefers-Color-Scheme: dark` to Google, and inject nothing; sites with a dark theme show it themselves.
- **Blocking:** ads and trackers, and cookie banners, are blocked with `WKContentRuleList`s compiled from the downloaded lists. They are two separate rule sets on two separate toggles.
- **Hardware keyboard:** ⌘T new tab, ⌘L the search sheet, ⌘W close tab, ⌘R reload, ⌘[ / ⌘] back and forward, ⌘F find on page, ⌘⇧\ the tabs screen; Esc folds the search sheet, the menu, or the find bar away. The page's own shortcuts work only while reading; every one shows in the system overlay (hold ⌘).

## 03 · Tabs
- **Layout:** a `TabStack` on the mist. The current tab is centred; the others sit to each side, with labels above.
- **Gestures:** fling up to close; tap to open; swipe sideways to move through the stack.
- **Bottom row:** the Archived chip (opens 09), the open count, and + (opens the launch search sheet, 01, on the mist, as a new tab). The row sits like the bars (foundations · bottom controls), its bottom edge `max(26, safe-area-bottom − 8)` above the physical bottom; the stack keeps clear of the status bar.
- **Private tab:** a long-press on + (or the menu's Private tile) opens the launch search for a private tab, "Private tab" in a glass capsule above the sheet. A private tab keeps nothing: no saved place in the stack, no snapshot, no recent searches, no Skim, no auto-archive, no favicon fetch. Its cookies and site data live in one in-memory store shared by private tabs and dropped with the last one. The bar's pill and the tab's label carry `eye.slash`; VoiceOver reads ", private" after the name. With a private tab open, the app switcher's picture is the mist with `eye.slash`.
- **Auto-archive:** tabs untouched for the set time move to Archive. The default is 1 day, adjustable from 12 hours to 30 days, ON by default.

## 04 · Skim page
- **Layout:** a scrolling page with background `skimBackground`. From top to bottom:
  - `PhotoHeader` (tiers 4a mosaic, 4b hero, 4c no photos)
  - `SkimHeader`
  - `SkimSection`s
  - "Sources" with a row of `SourceCard`s
- **Floating controls:** a trailing "Done" (`skim.done`, on a glass capsule) in a `ScreenHeader` control row at the top, with the `SkimQueryBar` under it, and the `SkimControlBar` at the bottom. Done leaves the page, the same as `cancelSkim()`.
- **Content rhythm:** an emoji, a **bold term**, " — ", a short claim, then citation dots. Every claim carries at least one dot.
- **Share:** creates a self-contained page (HTML snapshot) that includes its sources. Saving puts it in Bookmarks as a Skim page.
- **Availability:** Skim exists only on devices that can run Apple Foundation Models (iPhone 15 Pro and later, Apple Intelligence on, a supported language). Everywhere else every Skim entry point is hidden: there are no disabled states and no upsell.

## 05 · Menu
- **Opening:** the `MenuSheet` grows out of the bar. The bar stays at the base with ••• pressed.
- **Height:** hugs its content, with 14 pt above the bar.
- **Tiles:** Skim, Bookmark, Share, Mods, Private.
- **Groups:**
  - (ads & trackers, cookie banners, archive timing)
  - (search engine, Skim for me, Settings ›)
- **Bookmark tile:** a tap saves the page, with a light haptic and the icon filling in; a long-press opens Bookmarks (10).
- **Dismissing:** tap •••, swipe down, or tap the page.
- **Board fix:** the static board screen 05 shows too much space above the bar. The spec value of 14 pt wins.

## 06 · Mods
- **Background:** the mist.
- **Header:** "Mods" in a `ScreenHeader`, with "Done" at top right (`mods.done`). Section headings use `SectionLabel`; the cards are `GroupedBox`es; the installed empty state is `EmptyListState`.
- **Segments:** Directory | Installed · N.
- **Directory tab:** the `FeaturedModCard` (Google Answer Box), then "Popular this week" (`sectionTitle`) and a card of `ModRow`s.
- **Directory install:** while the entry's file is fetched and checked, the row's Get gives way to the 24 pt `MarkSpinner` (05 · 06). More than one can run at once, each row carrying its own mark; a Get for an entry already installing does nothing. The install stays on the Directory tab: when it lands, the row's Get becomes a popping `InstalledCheck` in place. An install that does not land shows one plain line under the card, with Get as the way to try again.
- **Footer:** the glass `InstallFooter` pill.
- **Installed tab:** the same rows, each with an on/off toggle and swipe-to-remove.
- **Link update:** an update to a link-installed script that adds any `@match`, `@include` or `@grant` it didn't have is held; the install sheet shows the new version with its new sites and grants, "Update" installs it and "Cancel" keeps the old one. Anything else updates silently.
- **Directory source:** a JSON index in a public GitHub repo. Every addition is reviewed through a pull request. It is fetched at most once a day.
- **Mod types:**
  - userscripts, injected with `WKUserScript` per matching host
  - filter lists, compiled to `WKContentRuleList`

## 07a · Welcome (first launch only)
- **Background:** the mist.
- **Anchor:** the block's top sits 0.23 of the height below the safe-area top (about 176 pt on a standard phone).
- **Centre:** the mark draws itself (`MarkSpinner`, played once), then "magpie" in `wordmark` and "The browser you shape." in `row` `textOnMistSecondary` settle in beneath it.
- **Bottom:** the `PrimaryCTA` "Get started", with "Free and open source. No account. Nothing collected." in `small` under it.

## 07b · Pick a search engine
- **Header:** a step label 26 pt below the safe-area top, then "Where should searches go?" in `screenTitle`, then "Pick one; you can switch any time from the menu."
- **Grid:** `EngineTile`s, two per row, in this fixed order: DuckDuckGo, Google, Brave Search, Kagi, Ecosia, Startpage, Bing, Other.
  - Each tile's note: No tracking / The usual / Own index / Paid, no ads / Plants trees / Google, privately / Microsoft / Any, by search URL.
  - **Nothing is pre-selected. No engine pays for placement.**
- **Other:** asks for a search URL containing `%s`, then validates it. One typed without a scheme is taken as https; the only error is a missing `%s` ("The address needs %s where the query goes.").
- **CTA:** disabled until a tile is picked, then reads "Continue with {Engine}".

## 08 · Skim working
- **Background:** the drifting mist.
- **Centre:** the `MarkSpinner` at 96 pt, with the query title (`skimWorkingTitle`) fading in under it.
- **Progress:** three source favicons fill in one by one as each page is read, with "Reading 3 pages" in `small`.
- **Bottom:** a Cancel button.
- **Nothing else:** no carousels, chips or typed text.
- **Duration:** about 30–60 s. When done, it plays 05 · Skim finishes.

## 09 · Archive
- **Header:** "Archive" in a `ScreenHeader`, with "Done" at top right (`archive.done`).
- **List:** rows on the mist, grouped by `SectionLabel` (Today, Yesterday, Earlier this week, then one per month, newest first). A month band names its year only outside the current year: "October", "October 2025". Each row: favicon, title, site, time. A row dated in the current year never shows the year ("Sep 30"); an older one does ("Sep 30, 2025").
- **Actions:** tap a row to restore the tab; swipe to delete.
- **Search:** the `BottomSearchPill` with "Search archived tabs" searches titles and addresses; the pill rides the keyboard.
- **Retention:** 30 days, then deleted.

## 10 · Bookmarks
- **Header:** "Bookmarks" in a `ScreenHeader`, with Edit (top left) and Done (top right). Done leaves, as the back swipe does (`bookmarks.done`). While editing, the leading label reads "Save", never "Done". An open folder swaps Edit for Back; Done stays.
- **Folders:** a "Folders" section of `FolderRow`s, then "Recently added", mixing `ListRow`s and `SkimPageRow`s.
- **Edit mode:** adds "New folder", rename, reorder and delete.
- **Search:** the `BottomSearchPill` with "Search bookmarks"; the pill rides the keyboard.

## 11 · Settings
- **Background:** the mist, with grouped boxes (`GroupedBox`, frosted).
- **Header:** "Settings" in a `ScreenHeader`, with Done. Its pages carry Back at the leading edge and the same Done, which closes Settings.
- **Default browser:** the `DefaultBrowserCard` sits on top until Magpie is the default.
- **Groups:**
  - **Search:** Search engine › · Suggestions [toggle] · Skim for me [toggle]
  - **Privacy:** Ads & trackers [toggle] · Cookie banners [toggle] · Filter lists ("Updated 2 h ago" ›)
  - **Tabs & more:** Archive tabs after ("1 day" ›) · Passwords (`key`; "iOS Passwords" ›, which opens iOS Passwords) · About Magpie ("1.0 · MPL-2.0" ›)
- There is no account and no sync.

## 12 · Install from URL
- **Presentation:** a system sheet over the real Mods page, which stays visible behind it, blurred about 2.5 pt and dimmed with `scrim`.
- **Sheet contents:**
  - the `Grabber` and the title "Install from URL"
  - a URL field with a 1.5 pt `ink` ring
  - a preview card: icon, name, "Script · by l.marsh · v1.2", then rows for "Runs on" (hosts from the `@match` / `@include` metadata) and "Can" (a plain-language list of permissions)
  - a warning box (`warningBackground`): "**Not in the directory.** Nobody has reviewed this mod. Only install it if you trust where it came from."
  - Cancel (ghost) and Install (ink)
- **Install:** plays 05 · Mod installed.

## Edge states (13–17)
Every edge state follows one pattern: one plain line saying what happened, and one way forward. No illustrations; nothing playful.

### 13 · Mods · Installed
- **Layout:** the same card of `ModRow`s as the Directory tab, with a trailing `Toggle` instead of Get.
- **Toggle off:** keeps the mod but stops it running.
- **Swipe left:** removes the mod.
- **Mods added from a link:** keep a small warm "Not reviewed" tag after the name (`warningBackground` / `warningText`, 10 pt semibold, radius 6). The author line ends "· from a link".
- **Hint under the card:** "Swipe a mod left to remove it. Off keeps it, but it stops running." (`small`, `textOnMistSecondary`)
- **Footer:** the `InstallFooter` stays.

### 14 · Empty list (Archive; same for Bookmarks and Installed)
- **Layout:** the header stays. A centred block sits on the mist with its top at 0.35 of the screen's safe height (about 270 pt on a standard phone), laid over the whole screen rather than under the header: a 34 pt line icon in `labelOnMist`, a title in 16 pt semibold, and one line in `meta`.
- **No search pill** when there's nothing to search.
- **A search that matches nothing** shows the same block with "No results" and one line naming the list, while the pill stays to take the query back.
- **Copy:**
  - Archive: "Nothing archived yet" / "Tabs you leave alone for a day land here, and stay for 30 days."
  - Bookmarks and Installed: see 06.

### 15 · Page can't load
- **Layout:** Magpie's own page on `skimBackground` (dark #121316), centred: a 40 pt globe-with-slash line icon in `textTertiary`, a title in 18 pt semibold, one line in `body` `textSecondary`, and an ink capsule "Try again" (paper in dark), never under 44 tall.
- **The bar stays**, at its default tint.
- **Offline:** the page reloads by itself when the connection returns (`NWPathMonitor`).
- **Other failures** follow the same layout with different copy (see 06).

### 16 · Skim couldn't finish
- **Layout:** the Skim working scene with the mark **standing still** at 55% opacity, the title, then one line in `meta` saying why.
- **Actions:** "Show search results" (the primary button) and "Try again" (text button), and a trailing "Done" (`skim.done`) that leaves, the same as `cancelSkim()`.
- **Trigger:** fewer than 2 pages could be read, or the model refused. Never show a half-built page.

### 17 · Install failed
- **Layout:** the install sheet with the URL field kept. In the preview's place, a solid card with a bold reason and one line on what Magpie needs.
- **Install** stays disabled at 30% until the link parses as a userscript or filter list.

---

## Dark mode, all screens
- **Mist:** turns ink, with teal glowing through (01 Mist dark column).
- **Glass:** goes smoky. The system handles this.
- **Ink elements flip to paper:** toggles, icon squares, the primary Skim pill, the Search key, the + button, primary CTAs and the Install button.
- **Solid cards:** become #1C1D21. The Skim page background becomes #121316.
- **Text:** follows the Neutrals table.
- **Sheen:** unchanged.
- **Web pages:** keep their own appearance and are never inverted.
