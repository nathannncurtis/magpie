import SwiftUI

/// The downloads: saved files as plain rows on the mist, newest first. Tapping a row
/// opens the file in QuickLook; a swipe deletes it.
struct DownloadsScreen: View {
    let store: DownloadStore
    var onDone: () -> Void

    /// The delete just made, on offer for an undo.
    @State private var undo: UndoNotice?
    @State private var bottomInset: CGFloat = 0

    private enum ScreenMetrics {
        /// The nav row at the head of the screen.
        static let navHeight: CGFloat = 36
        static let navLeading: CGFloat = 16
        static let navTrailing: CGFloat = 18
        static let titleTop: CGFloat = 2
        static let titleBottom: CGFloat = 10
        /// The least a control measures, so a tap never lands on less.
        static let tapTarget: CGFloat = 44
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MistBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                navRow
                Text(String(localized: "Downloads"))
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.Spacing.insetList)
                    .padding(.top, ScreenMetrics.titleTop)
                    .padding(.bottom, ScreenMetrics.titleBottom)
                    .accessibilityIdentifier("downloads.title")
                if !store.files.isEmpty {
                    list
                }
            }
            .readableWidth()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if store.files.isEmpty {
                EmptyListState(
                    icon: "arrow.down.circle",
                    title: String(localized: "No downloads yet"),
                    message: String(
                        localized: "Files you save from a page land here, and in the Files app.")
                )
                .accessibilityIdentifier("downloads.empty")
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.bottom
        } action: {
            bottomInset = $0
        }
        .undoNotice($undo, bottomInset: bottomInset)
    }

    private var navRow: some View {
        HStack {
            Spacer()
            Button(action: onDone) {
                Text(String(localized: "Done"))
                    .frame(
                        minWidth: ScreenMetrics.tapTarget,
                        minHeight: ScreenMetrics.tapTarget,
                        alignment: .trailing
                    )
                    .contentShape(.rect)
            }
            .font(Typography.buttonPill)
            .foregroundStyle(Palette.textPrimary)
            .accessibilityIdentifier("downloads.done")
        }
        .padding(.leading, ScreenMetrics.navLeading)
        .padding(.trailing, ScreenMetrics.navTrailing)
        .frame(minHeight: ScreenMetrics.navHeight)
    }

    private var list: some View {
        List {
            ForEach(Array(store.files.enumerated()), id: \.element.id) { index, file in
                DownloadRow(file: file, showsSeparator: index > 0) { store.open(file.url) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onDelete { offsets in
                let files = store.files
                let trashed = offsets.compactMap { index in
                    files.indices.contains(index) ? store.trash(files[index]) : nil
                }
                if !trashed.isEmpty {
                    undo = .deleted { trashed.forEach { store.restore($0) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloads.list")
    }
}

/// One saved file as a row: a file glyph, its name, then its size and when it came.
private struct DownloadRow: View {
    let file: DownloadStore.File
    let showsSeparator: Bool
    var onOpen: () -> Void

    private enum RowMetrics {
        static let tile: CGFloat = 26
        static let gap: CGFloat = 12
        static let verticalPadding: CGFloat = 8
    }

    var body: some View {
        HStack(spacing: RowMetrics.gap) {
            RoundedRectangle(cornerRadius: ListFavicon.faviconRadius(RowMetrics.tile), style: .continuous)
                .fill(Palette.separatorOnMist)
                .frame(width: RowMetrics.tile, height: RowMetrics.tile)
                .overlay {
                    Image(systemName: "doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.labelOnMist)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(Typography.small)
                    .foregroundStyle(Palette.textOnMistSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: RowMetrics.gap)
        }
        .padding(.vertical, RowMetrics.verticalPadding)
        .padding(.horizontal, Metrics.Spacing.insetList)
        .overlay(alignment: .top) {
            if showsSeparator {
                Rectangle()
                    .fill(Palette.separatorOnMist)
                    .frame(height: 0.5)
                    .padding(.leading, RowMetrics.tile + RowMetrics.gap + Metrics.Spacing.insetList)
            }
        }
        .rowPress(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("downloads.row.\(file.name)")
    }

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        return size + " · " + file.date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    DownloadsScreen(store: DownloadStore(), onDone: {})
}
