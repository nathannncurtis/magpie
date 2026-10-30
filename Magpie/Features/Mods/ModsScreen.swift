import SwiftUI

/// The mods screen: the mist, the Directory and Installed segments, and the glass footer
/// that opens the install-from-URL sheet (04 · 06, 04 · 13). Directory installs land on
/// the Installed segment with the new row's check popping (05 · 06).
struct ModsScreen: View {

    /// Layout numbers from the board.
    private enum Layout {
        /// The header's inset from the sides.
        static let headerInset: CGFloat = 20
        /// The segments' inset from the sides.
        static let segmentInset: CGFloat = 20
        /// The scrolling content's inset from the sides.
        static let contentInset: CGFloat = 14
        /// The card of rows' own side padding.
        static let cardPadding: CGFloat = 14
        /// The section title's margins: 20 above, 8 below, 6 at the sides.
        static let sectionTop: CGFloat = 20
        static let sectionBottom: CGFloat = 8
        static let sectionSide: CGFloat = 6
        /// The hint line's margins under the installed card.
        static let hintInset: CGFloat = 8
        /// How far down the empty state sits from the content's top.
        static let emptyOffset: CGFloat = 140
        static let footerInset: CGFloat = 14
    }

    let directory: ModDirectory
    /// The installed mods.
    let store: ModStore
    var onDone: () -> Void

    private enum Segment: Int {
        case directory = 0
        case installed = 1
    }

    @State private var segment = Segment.directory
    @State private var showingInstallSheet = false
    /// The mod whose install just landed, for the confirmation row.
    @State private var landedModID: String?
    /// The mods installed while this screen has been up, so their checks pop.
    @State private var newlyInstalled: Set<String> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            MistBackground()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                SegmentedControl(
                    options: [ModsCopy.directory, ModsCopy.installedSegment(store.mods.count)],
                    selection: Binding(
                        get: { segment.rawValue },
                        set: { segment = Segment(rawValue: $0) ?? .directory }
                    )
                )
                .padding(.horizontal, Layout.segmentInset)
                .padding(.bottom, 10)
                ScrollView {
                    Group {
                        switch segment {
                        case .directory: directoryContent
                        case .installed: installedContent
                        }
                    }
                    .padding(.horizontal, Layout.contentInset)
                    .padding(.bottom, 16)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InstallFooter(action: { showingInstallSheet = true })
                .padding(.horizontal, Layout.footerInset)
                .padding(.bottom, 6)
        }
        .sheet(isPresented: $showingInstallSheet) {
            InstallSheet { draft in
                store.install(draft)
                land(draft.id)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackgroundInteraction(.disabled)
        }
        .onChange(of: showingInstallSheet) { _, showing in
            if !showing { holdLandedCheck() }
        }
        .onDisappear { newlyInstalled.removeAll() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ModsCopy.title)
                .font(Typography.screenTitleSmall)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Button(ModsCopy.done, action: onDone)
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("mods.done")
        }
        .padding(.horizontal, Layout.headerInset)
        .padding(.bottom, 14)
    }

    // MARK: Directory

    private var directoryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let featured = directory.featured {
                FeaturedModCard(
                    mod: featured,
                    installed: store.mod(id: featured.id) != nil,
                    onGet: { install(featured) }
                )
                .padding(.bottom, 4)
            }
            Text(ModsCopy.popularThisWeek)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
                .padding(
                    EdgeInsets(
                        top: Layout.sectionTop, leading: Layout.sectionSide,
                        bottom: Layout.sectionBottom, trailing: Layout.sectionSide))
            rowsCard(
                directory.popular.map { entry in
                    ModRow(
                        icon: entry.icon,
                        name: entry.name,
                        summary: entry.descriptionText,
                        authorLine: ModsCopy.authorLine(kind: entry.kind, author: entry.author, fromLink: false),
                        trailing: trailing(for: entry))
                })
        }
    }

    /// What a directory row carries: the check once installed, else Get.
    private func trailing(for entry: DirectoryMod) -> ModRow.Trailing {
        store.mod(id: entry.id) != nil
            ? .installed(pops: newlyInstalled.contains(entry.id))
            : .get(action: { install(entry) })
    }

    /// A directory install: the entry's file, verified against the index's digest, then
    /// the row's Get becomes a popping check.
    private func install(_ entry: DirectoryMod) {
        Task { @MainActor in
            guard let body = try? await directory.download(entry) else { return }
            guard let draft = entry.draft(body: body) else { return }
            store.install(draft)
            newlyInstalled.insert(draft.id)
        }
    }

    // MARK: Installed

    private var installedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.mods.isEmpty {
                emptyState
            } else {
                rowsCard(
                    store.mods.map { mod in
                        installedRow(mod)
                    })
                Text(ModsCopy.swipeHint)
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .padding(
                        EdgeInsets(
                            top: 12, leading: Layout.hintInset, bottom: 0, trailing: Layout.hintInset))
            }
        }
    }

    private func installedRow(_ mod: InstalledMod) -> some View {
        let landed = mod.id == landedModID
        return ModRow(
            icon: mod.icon,
            name: mod.name,
            summary: mod.summary,
            authorLine: ModsCopy.authorLine(
                kind: mod.kind, author: mod.author, fromLink: mod.source.isLink),
            notReviewed: mod.source.isLink,
            trailing: installedTrailing(for: mod, landed: landed),
            onRemove: {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.settle.animation) {
                    store.remove(id: mod.id)
                }
            }
        )
        .transition(landed ? landingTransition : .opacity)
    }

    /// An installed row carries its switch; the one that has just landed carries the
    /// popping check until the confirmation settles (05 · 06).
    private func installedTrailing(for mod: InstalledMod, landed: Bool) -> ModRow.Trailing {
        if landed { return .installed(pops: true) }
        return .toggle(
            isOn: Binding(
                get: { mod.enabled },
                set: { store.setEnabled($0, id: mod.id) }
            ))
    }

    /// The confirmation row's arrival: it rises 8 pt and fades in. Reduce Motion: a plain
    /// crossfade.
    private var landingTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .offset(y: 8).combined(with: .opacity), removal: .opacity)
    }

    // Board 14's empty pattern: a line icon, a 16 pt title, one line, far down.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Palette.labelOnMist)
            Text(ModsCopy.emptyTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(ModsCopy.emptyLine)
                .font(Typography.meta)
                .foregroundStyle(Palette.textOnMistSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Layout.emptyOffset)
        .accessibilityIdentifier("mods.empty")
    }

    // MARK: Shared

    /// A solid card of rows, separators between them (board's `.mcard`).
    private func rowsCard<Row: View>(_ rows: [Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                row
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Palette.separator)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, Layout.cardPadding)
        .padding(.vertical, 4)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .shadow(color: Palette.tabCardShadow, radius: 15, y: 14)
    }

    /// An install from the sheet has landed: the Installed segment takes over, and the
    /// new row rises in with its check popping.
    private func land(_ id: String) {
        newlyInstalled.insert(id)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.settle.animation) {
            segment = .installed
            landedModID = id
        }
    }

    /// The check holds behind the dropping sheet long enough to be seen, then gives way
    /// to the row's switch. Counted from the sheet's drop, not the install tap.
    private func holdLandedCheck() {
        guard let id = landedModID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if landedModID == id {
                withAnimation(.easeInOut(duration: 0.2)) {
                    landedModID = nil
                }
            }
        }
    }
}

extension ModSource {
    /// Whether the mod came from a pasted link, which stays marked Not reviewed.
    var isLink: Bool {
        if case .link = self { return true }
        return false
    }
}
