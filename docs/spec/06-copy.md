# 06 · Copy

## Voice
- **Sentence case.** Titles, rows and buttons: "Clear browsing data", not "Clear Browsing Data". Proper nouns keep their capitals.
- **American spelling.** "License", "color".
- **One name per thing.** The menu and Settings use the same words for the same row: "Ads & trackers", "Cookie banners", "Skim for me", "Desktop site", "History", "Search engine", "Archive tabs after".
- **Terse and plain.** Write in short sentences; semicolons are fine.
- **No exclamation marks.** None anywhere.
- **No hype.** No "AI-powered", no "supercharge", no "magic".
- **AI framing:** never call Magpie anti-AI, and never call it an AI browser.
- **Vocabulary:** no Zen vocabulary.
- **Errors:** say what happened and what to do, in one line.

Put all strings in `Localizable.xcstrings`; English only at 1.0.

## Strings on the boards

| Where | String |
|---|---|
| Welcome | "magpie" · "The browser you shape." · "Get started" · "Free and open source. No account. Nothing collected." |
| Engine picker | "Where should searches go?" · "Pick one; you can switch any time from the menu." · tile notes (04 · 07b) · "Other" / "Any, by search URL" · "Continue with {engine}" |
| Search | Skim pill: "Skim" |
| Menu | Tiles: "Skim" · "Bookmark" · "Share" · "Mods"; rows: "Ads & trackers" · "Cookie banners" · "Archive tabs after" / "1 day" · "Search engine" · "Skim for me" · "Desktop site" · "History" |
| Tabs | "Archived · {n}" · "{n} open" |
| Skim working | "Reading {n} pages" · "Cancel" |
| Skim page | "From {n} pages · read on this phone" · "Sources" · "Dig deeper · up to 10" |
| Archive | "Archive" · "Yesterday" · "Earlier this week" · "Search archived tabs" · "Done" |
| History | "History" · "Search history" · "Clear history…" · "Clear all history?" · "Clear history" |
| Clear browsing data | "Clear browsing data" · "History" · "Cookies and site data" · "Cache" · "Clear" · "Clear browsing data?" / "This can't be undone. Open pages reload." · "Cleared." |
| Bookmarks | "Bookmarks" · "Edit" · "Folders" · "Recently added" · "New folder" · "Skim page · {folder}" · "Search bookmarks" |
| Settings | "Settings" · "Make Magpie your default browser" / "Links from other apps open here. Set in iOS Settings." / "Open" · section labels: "Search", "Privacy", "Tabs & more" · rows (04 · 11) · "Updated {time} ago" · "iOS Passwords" · "About Magpie" · "{version} · MPL-2.0" |
| Mods | "Mods" · "Directory" · "Installed · {n}" · "Popular this week" · "Get" · "Install from URL" |
| Install sheet | "Install from URL" · "Runs on" · "Can" · "Not in the directory." · "Nobody has reviewed this mod. Only install it if you trust where it came from." · "Cancel" · "Install" · confirmation: "Installed just now" |
| Mod author line | "{script\|filter list} · {author}" |

## Edge states
| Where | String |
|---|---|
| Mods · Installed | "Not reviewed" · "{type} · {author} · from a link" · "Swipe a mod left to remove it. Off keeps it, but it stops running." |
| Mods · Directory install failed | "{name} didn't install. Tap Get to try again." |
| Empty Archive | "Nothing archived yet" / "Tabs you leave alone for a day land here, and stay for 30 days." |
| No search results | "No results" / "Nothing in the archive matches that search." · "No bookmarks match that search." · "Nothing in your history matches that search." |
| Empty Bookmarks | "No bookmarks yet" / "Tap Bookmark in the menu to keep a page here." |
| Empty History | "No history yet" / "Pages you visit show up here." |
| Empty Installed | "Nothing installed" / "Mods from the directory or a link show up here." |
| Offline | "Can't reach {host}" / "You're offline. It'll load when you're back." · "Try again" |
| Stalled load | "This page stopped loading" / "It took too long. Try again in a moment." · "Try again" |
| Renderer died twice | "This page stopped working" / "Something went wrong showing it. Try again." · "Try again" |
| Skim failed | "Only {n} of {m} pages could be read. That's not enough to Skim." · "Show search results" · "Try again" |
| Install failed (web page) | "That's a web page, not a mod." / "Magpie needs a link to a userscript (ending in .user.js) or a filter list." |
| Skim failed (other causes) | "Couldn't put those pages together. Try again." · "Those pages are too long to read together. Try a narrower search." · "Search results didn't load. Check your connection and try again." · "That didn't work. Try again." |
| Install failed (other) | "No answer from that link." / "Check the address, or try again in a moment." · "That script runs nowhere." / "It names no site in @match or @include, so Magpie has nowhere to run it." |
