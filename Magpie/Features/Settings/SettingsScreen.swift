import SwiftUI

/// Settings (04 · 11): the mist, Done at the top right, the default-browser card, and the
/// three groups. Its pages — the engine list, filter lists, the archive picker, About —
/// push inside it with the bar hidden and a back button of their own.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var path: [SettingsPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsScaffold(title: "Settings", trailing: { done }) {
                DefaultBrowserCard()
                SettingsSectionLabel(title: "Search")
                SettingsGroup {
                    engineRow
                        .accessibilityIdentifier("settings.engine")

                    toggleRow(
                        icon: .symbol("magnifyingglass"), title: "Suggestions",
                        id: "settings.suggestions", isDivided: true,
                        isOn: Binding(
                            get: { model.preferences.suggestionsEnabled },
                            set: { model.preferences.suggestionsEnabled = $0 }))

                    toggleRow(
                        icon: .mark, title: "Skim for me",
                        id: "settings.skim", isDivided: false,
                        isOn: Binding(
                            get: { model.preferences.skimEnabled },
                            set: { model.preferences.skimEnabled = $0 }))
                }

                SettingsSectionLabel(title: "Privacy")
                SettingsGroup {
                    toggleRow(
                        icon: .symbol("shield.lefthalf.filled"), title: "Ads & trackers",
                        id: "settings.ads", isDivided: true,
                        isOn: Binding(
                            get: { model.blocker.blocksAdsAndTrackers },
                            set: { model.blocker.blocksAdsAndTrackers = $0 }))
                    toggleRow(
                        icon: .cookie, title: "Cookie banners",
                        id: "settings.cookies", isDivided: true,
                        isOn: Binding(
                            get: { model.blocker.blocksCookieBanners },
                            set: { model.blocker.blocksCookieBanners = $0 }))

                    SettingsRow(icon: .symbol("cellularbars"), title: "Filter lists") {
                        Text(
                            ContentBlocker.updatedText(
                                from: model.blocker.lastUpdated, now: .now)
                        )
                        .font(Typography.row)
                        .foregroundStyle(Palette.textOnMistSecondaryMeta)
                        SettingsChevron()
                    }
                    .action { path.append(.filterLists) }
                    .accessibilityIdentifier("settings.filterLists")
                }

                SettingsSectionLabel(title: "Tabs & more")
                SettingsGroup {
                    SettingsRow(icon: .symbol("archivebox"), title: "Archive tabs after") {
                        rowValue(Preferences.archiveIntervalLabel(model.preferences.archiveInterval))
                        SettingsChevron()
                    }
                    .action { path.append(.archivePicker) }
                    .accessibilityIdentifier("settings.archive")

                    SettingsRow(icon: .symbol("bookmark"), title: "Passwords") {
                        rowValue("iOS Passwords")
                        SettingsChevron()
                    }
                    .action { openPasswords() }
                    .accessibilityIdentifier("settings.passwords")

                    SettingsRow(icon: .symbol("link"), title: "About Magpie") {
                        rowValue("\(Self.version) · MPL-2.0")
                        SettingsChevron()
                    }
                    .action { path.append(.about) }
                    .accessibilityIdentifier("settings.about")
                }
            }
            .navigationDestination(for: SettingsPage.self) { page in
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
    }

    /// The pages Settings pushes.
    enum SettingsPage: Hashable {
        case engineList
        case filterLists
        case archivePicker
        case about
    }

    private var engineRow: some View {
        SettingsRow(icon: .symbol("globe"), title: "Search engine") {
            rowValue(model.preferences.searchEngine.displayName)
            SettingsChevron()
        }
        .action { path.append(.engineList) }
    }

    private func toggleRow(
        icon: SettingsIcon, title: String, id: String, isDivided: Bool, isOn: Binding<Bool>
    ) -> some View {
        SettingsRow(icon: icon, title: title, isDivided: isDivided) {
            Toggle(title, isOn: isOn)
                .toggleStyle(SettingsToggleStyle())
                .labelsHidden()
                .accessibilityLabel(title)
        }
        .accessibilityIdentifier(id)
    }

    private func rowValue(_ text: String) -> some View {
        Text(text)
            .font(Typography.row)
            .foregroundStyle(Palette.textOnMistSecondaryMeta)
    }

    private var done: some View {
        Button("Done") { model.showsSettings = false }
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
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
                topRow
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                ScrollView {
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("settings.back")
            }
            Spacer()
            trailing()
        }
    }
}
