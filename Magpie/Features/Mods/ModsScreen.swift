import SwiftUI

/// The mods screen: the mist, the Directory and Installed segments, and the glass footer
/// that opens the install-from-URL sheet (04 · 06, 04 · 13). A directory install stays
/// on the Directory segment, its row's Get giving way to a popping check (05 · 06); only
/// the sheet's install lands on the Installed segment.
struct ModsScreen: View {

    /// Layout numbers from the board.
    private enum Layout {
        /// The hint line's margins under the installed card.
        static let hintInset: CGFloat = 8
        /// The card of rows' own side padding.
        static let cardPadding: CGFloat = 14
        /// The scroll's own margin below its content, before the footer's clearance.
        static let contentBottom: CGFloat = 16
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
    /// The mods whose files are being fetched and checked at once, so each row
    /// carries its own mark without resetting another's.
    @State private var installingIDs: Set<String> = []
    /// The mod whose install did not land, for the one line under the card.
    @State private var failedID: String?
    @State private var bottomInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            MistBackground()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(
                    title: ModsCopy.title, titleID: "mods.title",
                    trailing: { HeaderDoneButton(id: "mods.done", action: onDone) })
                SegmentedControl(
                    options: [ModsCopy.directory, ModsCopy.installedSegment(store.mods.count)],
                    selection: Binding(
                        get: { segment.rawValue },
                        set: { segment = Segment(rawValue: $0) ?? .directory }
                    )
                )
                .padding(.horizontal, Metrics.Spacing.insetList)
                .readableWidth()
                .padding(.bottom, 10)
                ScrollView {
                    Group {
                        switch segment {
                        case .directory: directoryContent
                        case .installed: installedContent
                        }
                    }
                    .readableWidth()
                    .padding(.bottom, scrollBottom)
                }
            }
            if segment == .installed && store.mods.isEmpty {
                // The quiet block lays over the whole screen, held to the safe height.
                EmptyListState(
                    icon: "puzzlepiece", title: ModsCopy.emptyTitle, message: ModsCopy.emptyLine
                )
                .padding(.bottom, bottomInset)
                .allowsHitTesting(false)
                .accessibilityIdentifier("mods.empty")
            }
            // The footer rides the bottom edge the way the other floating bars do;
            // the scroll's padding keeps its last row clear of it.
            VStack(spacing: 0) {
                Spacer()
                InstallFooter(action: { showingInstallSheet = true })
                    .padding(.horizontal, Layout.footerInset)
                    .readableWidth()
                    .padding(
                        .bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset))
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showingInstallSheet) {
            InstallSheet { draft in
                store.install(draft)
                land(draft.id)
            }
            .presentationDragIndicator(.hidden)
            .presentationBackgroundInteraction(.disabled)
        }
        // A link update that would run on more sites, or ask for more, waits here for
        // the user's word; cancel keeps the version already installed.
        .sheet(
            item: Binding(
                get: { store.pendingUpdate },
                set: { if $0 == nil { store.cancelPendingUpdate() } })
        ) { pending in
            InstallSheet(update: pending) { _ in
                store.confirmPendingUpdate()
            }
            .presentationDragIndicator(.hidden)
            .presentationBackgroundInteraction(.disabled)
        }
        .onChange(of: showingInstallSheet) { _, showing in
            if !showing { holdLandedCheck() }
        }
        .onChange(of: segment) { _, _ in
            // The check pops on the install's own landing; a revisit shows it still.
            newlyInstalled.removeAll()
        }
        .onDisappear { newlyInstalled.removeAll() }
    }

    /// The scroll's bottom padding: its own margin plus enough clearance for the
    /// footer to float over the content without covering its last row.
    private var scrollBottom: CGFloat {
        Layout.contentBottom
            + Metrics.Bar.installFooterHeight
            + Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset)
    }

    // MARK: Directory

    private var directoryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let featured = directory.featured {
                FeaturedModCard(
                    mod: featured,
                    installed: store.mod(id: featured.id) != nil,
                    fetching: installingIDs.contains(featured.id),
                    pops: newlyInstalled.contains(featured.id),
                    onGet: { install(featured) }
                )
                .padding(.horizontal, Metrics.Spacing.insetList)
            }
            SectionLabel(title: ModsCopy.popularThisWeek)
            rowsCard(directory.popular) { entry in
                ModRow(
                    icon: entry.icon,
                    name: entry.name,
                    summary: entry.descriptionText,
                    authorLine: ModsCopy.authorLine(kind: entry.kind, author: entry.author, fromLink: false),
                    trailing: trailing(for: entry))
            }
            if let failed = failedMod {
                Text(ModsCopy.installFailedLine(failed.name))
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .padding(
                        EdgeInsets(
                            top: 12,
                            leading: Metrics.Spacing.insetList + Layout.hintInset,
                            bottom: 0,
                            trailing: Metrics.Spacing.insetList + Layout.hintInset)
                    )
                    .accessibilityIdentifier("mods.installFailed")
            }
        }
    }

    /// The mod whose install did not land, if the directory still knows it.
    private var failedMod: DirectoryMod? {
        failedID.flatMap(directory.entry(id:))
    }

    /// What a directory row carries: the check once installed, the mark while its
    /// file is fetched and checked, else Get.
    private func trailing(for entry: DirectoryMod) -> ModRow.Trailing {
        if store.mod(id: entry.id) != nil {
            return .installed(pops: newlyInstalled.contains(entry.id))
        }
        if installingIDs.contains(entry.id) {
            return .fetching
        }
        return .get(action: { install(entry) })
    }

    /// A directory install: the entry's file, verified against the index's digest, then
    /// the row's Get becomes a popping check. While the file is fetched and checked the
    /// row carries the mark; if nothing comes of it, one plain line says so and Get is
    /// the way to try again. Several can run at once; a Get for an entry already
    /// installing does nothing.
    private func install(_ entry: DirectoryMod) {
        guard !installingIDs.contains(entry.id) else { return }
        installingIDs.insert(entry.id)
        failedID = nil
        Task { @MainActor in
            defer { installingIDs.remove(entry.id) }
            guard
                let body = try? await directory.download(entry),
                let draft = entry.draft(body: body)
            else {
                failedID = entry.id
                return
            }
            store.install(draft)
            newlyInstalled.insert(draft.id)
        }
    }

    // MARK: Installed

    private var installedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.mods.isEmpty {
                rowsCard(store.mods) { mod in
                    installedRow(mod)
                }
                Text(ModsCopy.swipeHint)
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .padding(
                        EdgeInsets(
                            top: 12, leading: Metrics.Spacing.insetList + Layout.hintInset,
                            bottom: 0, trailing: Metrics.Spacing.insetList + Layout.hintInset))
            }
        }
    }

    private func installedRow(_ mod: InstalledMod) -> some View {
        let landed = mod.id == landedModID
        return ModRow(
            icon: mod.icon,
            name: mod.name,
            summary: mod.summary,
            authorLine: landed
                ? ModsCopy.installedJustNow
                : ModsCopy.authorLine(
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

    // MARK: Shared

    /// A grouped box of rows, hairlines between them. Rows are identified by the mod each
    /// holds, so a row keeps its state as the list moves.
    private func rowsCard<Item: Identifiable, Row: View>(
        _ items: [Item], @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        GroupedBox {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .padding(.horizontal, Layout.cardPadding)
                if index < items.count - 1 {
                    Rectangle()
                        .fill(Palette.separatorOnMist)
                        .frame(height: 0.5)
                        .padding(.horizontal, Layout.cardPadding)
                }
            }
        }
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
            // The UI tests hold it further, until their shot has caught it.
            guard !UITestEnvironment.holdsInstallCheck, landedModID == id else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                landedModID = nil
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
