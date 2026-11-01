import SwiftUI

/// Settings (04 · 11): the mist, Done at the top right, the default-browser card, and the
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
            SettingsScaffold(title: String(localized: "Settings"), trailing: { done }) {
                DefaultBrowserCard()
                SettingsSectionLabel(title: String(localized: "Search"))
                SettingsGroup {
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

                SettingsSectionLabel(title: String(localized: "Privacy"))
                SettingsGroup {
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

                    SettingsRow(icon: .symbol("cellularbars"), title: String(localized: "Filter lists")) {
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
                }

                SettingsSectionLabel(title: String(localized: "Tabs & more"))
                SettingsGroup {
                    SettingsRow(icon: .symbol("archivebox"), title: String(localized: "Archive tabs after")) {
                        rowValue(Preferences.archiveIntervalLabel(model.preferences.archiveInterval))
                        SettingsChevron()
                    }
                    .action { path.append(.archivePicker) }
                    .accessibilityIdentifier("settings.archive")

                    SettingsRow(icon: .symbol("bookmark"), title: String(localized: "Passwords")) {
                        rowValue(String(localized: "iOS Passwords"))
                        SettingsChevron()
                    }
                    .action { openPasswords() }
                    .divided(true)
                    .accessibilityIdentifier("settings.passwords")

                    SettingsRow(icon: .symbol("link"), title: String(localized: "About Magpie")) {
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

    private var done: some View {
        Button("Done") { model.closeSettings() }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.leading, 8)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityIdentifier("settings.done")
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

/// The shared frame of Settings and its pages: the mist, a top row (Done, or back), the
/// title, and the scrolling content under it.
struct SettingsScaffold<Trailing: View, Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var showsBack = false
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        showsBack: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsBack = showsBack
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        ZStack {
            MistBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // The row stays 36 tall; the 44 pt targets in it spill 4 pt over its
                // edges, so it rides above what follows to keep the spill tappable.
                topRow
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .readableWidth()
                    .zIndex(1)
                ScrollView {
                    VStack {
                        Text(title)
                            .font(Typography.screenTitle)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                            .padding(.bottom, 10)
                        content()
                        Color.clear.frame(height: 32)
                    }
                    .readableWidth()
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var topRow: some View {
        HStack {
            if showsBack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                // The 44 pt target grows left over the row's inset, so the glyph holds
                // the place the 36 pt bar gave it instead of shifting with the frame.
                .padding(.leading, -4)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("settings.back")
            }
            Spacer()
            trailing()
        }
    }
}
