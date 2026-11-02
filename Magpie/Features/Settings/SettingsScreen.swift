import SwiftUI

/// Settings (04 · 11): the mist, the screen header with Done at the top right, the default-browser card, and the
/// three groups. Its pages — the engine list, filter lists, the archive picker, About —
/// push inside it with the bar hidden and a back button of their own.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Page]

    /// Opens on the page given, when a row elsewhere sent the user straight into one.
    init(opening page: Page? = nil) {
        _path = State(initialValue: page.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsScaffold(title: String(localized: "Settings")) {
                DefaultBrowserCard()
                SectionLabel(title: String(localized: "Search"))
                GroupedBox {
                    engineRow
                        .accessibilityIdentifier("settings.engine")

                    toggleRow(
                        icon: .symbol("magnifyingglass"), title: String(localized: "Suggestions"),
                        id: "settings.suggestions", isDivided: true,
                        isOn: Binding(
                            get: { model.preferences.suggestionsEnabled },
                            set: { model.preferences.suggestionsEnabled = $0 }))

                    toggleRow(
                        icon: .mark, title: String(localized: "Skim for me"),
                        id: "settings.skim", isDivided: true,
                        isOn: Binding(
                            get: { model.preferences.skimEnabled },
                            set: { model.preferences.skimEnabled = $0 }))
                }

                SectionLabel(title: String(localized: "Privacy"))
                GroupedBox {
                    toggleRow(
                        icon: .symbol("shield.lefthalf.filled"), title: String(localized: "Ads & trackers"),
                        id: "settings.ads", isDivided: false,
                        isOn: Binding(
                            get: { model.blocker.blocksAdsAndTrackers },
                            set: { model.blocker.blocksAdsAndTrackers = $0 }))
                    toggleRow(
                        icon: .cookie, title: String(localized: "Cookie banners"),
                        id: "settings.cookies", isDivided: true,
                        isOn: Binding(
                            get: { model.blocker.blocksCookieBanners },
                            set: { model.blocker.blocksCookieBanners = $0 }))

                    SettingsRow(icon: .symbol("list.bullet.rectangle"), title: String(localized: "Filter lists")) {
                        Text(
                            ContentBlocker.updatedText(
                                from: model.blocker.lastUpdated, now: .now)
                        )
                        .font(Typography.row)
                        .foregroundStyle(Palette.textOnMistSecondaryMeta)
                        SettingsChevron()
                    }
                    .action { path.append(.filterLists) }
                    .divided(true)
                    .accessibilityIdentifier("settings.filterLists")

                    SettingsRow(icon: .symbol("trash"), title: String(localized: "Clear browsing data")) {
                        SettingsChevron()
                    }
                    .action { path.append(.clearData) }
                    .divided(true)
                    .accessibilityIdentifier("settings.clearData")
                }

                SectionLabel(title: String(localized: "Tabs & more"))
                GroupedBox {
                    SettingsRow(icon: .symbol("archivebox"), title: String(localized: "Archive tabs after")) {
                        rowValue(Preferences.archiveIntervalLabel(model.preferences.archiveInterval))
                        SettingsChevron()
                    }
                    .action { path.append(.archivePicker) }
                    .accessibilityIdentifier("settings.archive")

                    SettingsRow(icon: .symbol("key"), title: String(localized: "Passwords")) {
                        rowValue(String(localized: "iOS Passwords"))
                        SettingsChevron()
                    }
                    .action { openPasswords() }
                    .divided(true)
                    .accessibilityIdentifier("settings.passwords")

                    SettingsRow(icon: .symbol("info.circle"), title: String(localized: "About Magpie")) {
                        rowValue("\(Self.version) · MPL-2.0")
                        SettingsChevron()
                    }
                    .action { path.append(.about) }
                    .divided(true)
                    .accessibilityIdentifier("settings.about")
                }
            }
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .engineList:
                    EngineListPage(preferences: model.preferences)
                case .filterLists:
                    FilterListsPage(blocker: model.blocker)
                case .archivePicker:
                    ArchivePickerPage(preferences: model.preferences)
                case .clearData:
                    ClearBrowsingDataPage()
                case .about:
                    AboutPage()
                }
            }
        }
        // Off Settings from its top page; a pushed page pops on the system's own swipe.
        .backSwipe(isEnabled: path.isEmpty) { model.closeSettings() }
    }

    /// The pages Settings pushes.
    enum Page: Hashable {
        case engineList
        case filterLists
        case archivePicker
        case clearData
        case about
    }

    private var engineRow: some View {
        SettingsRow(icon: .symbol("globe"), title: String(localized: "Search engine")) {
            rowValue(model.preferences.searchEngine.displayName)
            SettingsChevron()
        }
        .action { path.append(.engineList) }
    }

    private func toggleRow(
        icon: SettingsIcon, title: String, id: String, isDivided: Bool, isOn: Binding<Bool>
    ) -> some View {
        SettingsToggleRow(icon: icon, title: title, isOn: isOn)
            .divided(isDivided)
            .accessibilityIdentifier(id)
    }

    private func rowValue(_ text: String) -> some View {
        Text(text)
            .font(Typography.row)
            .foregroundStyle(Palette.textOnMistSecondaryMeta)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Passwords lives in its own app; when the scheme is not there, iOS Settings.
    private func openPasswords() {
        guard let passwords = URL(string: "passwords://") else { return }
        UIApplication.shared.open(passwords) { opened in
            if !opened, let settings = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settings)
            }
        }
    }
}

/// The shared frame of Settings and its pages: the mist, the screen header (back on a
/// page, Done always), and the scrolling content under it.
struct SettingsScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let title: String
    var showsBack = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            MistBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(
                    title: title, titleID: "settings.title",
                    leading: {
                        if showsBack {
                            HeaderBackButton(id: "settings.back") { dismiss() }
                        }
                    },
                    trailing: {
                        HeaderDoneButton(id: "settings.done") { model.closeSettings() }
                    })
                ScrollView {
                    VStack {
                        content()
                        Color.clear.frame(height: 32)
                    }
                    .readableWidth()
                }
            }
        }
        .navigationBarHidden(true)
    }
}
