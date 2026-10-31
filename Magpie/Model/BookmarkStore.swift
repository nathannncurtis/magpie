import Foundation
import Observation

/// One saved page: a plain link, or a Skim page with the hosts it was read from.
struct Bookmark: Identifiable, Codable, Equatable, Sendable {
    typealias ID = UUID

    /// What kind of page the bookmark keeps.
    enum Kind: Codable, Equatable, Sendable {
        /// A saved web page.
        case page
        /// A saved Skim page, carrying the hosts of the pages it was read from.
        case skim(sourceHosts: [String])
    }

    /// A stable identity across the list and persistence.
    let id: ID
    /// The saved page's address.
    var url: URL
    /// The page title as Magpie shows it.
    var title: String
    /// Where the site's favicon lives, once a pipeline supplies it.
    var faviconURL: URL?
    /// Cached favicon image data.
    var faviconData: Data?
    /// The folder the bookmark sits in, if any.
    var folderID: BookmarkFolder.ID?
    /// When the page was saved.
    var addedAt: Date
    /// A plain page or a Skim page.
    var kind: Kind

    init(
        id: ID = ID(),
        url: URL,
        title: String,
        faviconURL: URL? = nil,
        faviconData: Data? = nil,
        folderID: BookmarkFolder.ID? = nil,
        addedAt: Date,
        kind: Kind = .page
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconURL = faviconURL
        self.faviconData = faviconData
        self.folderID = folderID
        self.addedAt = addedAt
        self.kind = kind
    }

    /// The host without its www prefix, for subtitles and favicon fallbacks.
    var host: String? {
        guard let host = url.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// One bookmark folder, with its tint and place in the list.
struct BookmarkFolder: Identifiable, Codable, Equatable, Sendable {
    typealias ID = UUID

    /// A stable identity across the list and persistence.
    let id: ID
    /// The folder's name.
    var name: String
    /// The folder glyph's tint, one of the six presets.
    var tint: FolderTint
    /// The folder's place in the list, zero first.
    var order: Int

    init(id: ID = ID(), name: String, tint: FolderTint, order: Int) {
        self.id = id
        self.name = name
        self.tint = tint
        self.order = order
    }
}

/// The six folder tints. The values are the glyph's two panels: the dark back panel and
/// the light front panel. Folders keep their colour in dark mode, so neither value
/// follows the appearance.
enum FolderTint: String, Codable, CaseIterable, Sendable {
    /// The board's Kitchen orange.
    case orange
    /// The board's Reading blue.
    case blue
    /// The board's Work sage.
    case sage
    case rose
    case violet
    case teal

    /// The glyph's back panel.
    var back: UInt32 {
        switch self {
        case .orange: 0xF08A2A
        case .blue: 0x2F6BDF
        case .sage: 0x5E7550
        case .rose: 0xC2185B
        case .violet: 0x5C6BC0
        case .teal: 0x0C8484
        }
    }

    /// The glyph's front panel.
    var front: UInt32 {
        switch self {
        case .orange: 0xFFC27A
        case .blue: 0x7FB0FA
        case .sage: 0x9FB38E
        case .rose: 0xF2A0C0
        case .violet: 0xA5B2E8
        case .teal: 0x8AD4D0
        }
    }
}

/// The saved state of the bookmark store.
struct BookmarkIndex: Codable, Equatable, Sendable {
    /// The bookmarks, oldest first.
    var bookmarks: [Bookmark]
    /// The folders, in list order.
    var folders: [BookmarkFolder]
}

/// Where the bookmark store keeps its index.
///
/// Tests use the in-memory implementation; the app uses the file-system one.
protocol BookmarkPersistence: Sendable {
    /// The stored index, or nil when nothing has been written yet.
    func loadIndex() async throws -> BookmarkIndex?
    /// Replaces the stored index.
    func saveIndex(_ index: BookmarkIndex) async throws
}

/// A JSON index in Application Support.
actor FileSystemBookmarkPersistence: BookmarkPersistence {
    private let indexURL: URL

    /// `directory` overrides the store's home; tests point it at a scratch folder.
    init(directory: URL? = nil) {
        let support =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let home = (directory ?? support)
            .appendingPathComponent("Magpie/BookmarkStore", isDirectory: true)
        indexURL = home.appendingPathComponent("bookmarks.json")
    }

    func loadIndex() async throws -> BookmarkIndex? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return PersistedFile.decode(BookmarkIndex.self, from: indexURL, decoder: decoder)
    }

    func saveIndex(_ index: BookmarkIndex) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: indexURL, options: .atomic)
        } catch {
            PersistedFile.logWriteFailure(indexURL, error: error)
            throw error
        }
    }
}

/// Keeps the index in memory; nothing touches the disk.
actor InMemoryBookmarkPersistence: BookmarkPersistence {
    private var index: BookmarkIndex?

    init(index: BookmarkIndex? = nil) {
        self.index = index
    }

    func loadIndex() async throws -> BookmarkIndex? { index }
    func saveIndex(_ index: BookmarkIndex) async throws { self.index = index }
}

/// The saved bookmarks and their folders.
///
/// Every change schedules a write of the JSON index; all file work happens inside the
/// persistence actor. Methods that need the time take `now`, so tests drive the clock.
@MainActor
@Observable
final class BookmarkStore {

    /// The bookmarks, oldest first.
    private(set) var bookmarks: [Bookmark] = []
    /// The folders, in list order.
    private(set) var folders: [BookmarkFolder] = []

    private let persistence: BookmarkPersistence?
    private var indexWrite: Task<Void, Never>?

    /// An empty store with nothing behind it.
    init(persistence: BookmarkPersistence? = nil) {
        self.persistence = persistence
    }

    /// Reads the saved index into this store.
    func loadIndex() async {
        guard let persistence, let index = try? await persistence.loadIndex() else { return }
        bookmarks = index.bookmarks
        folders = index.folders.sorted { $0.order < $1.order }
    }

    // MARK: Bookmarks

    /// Saves a page. Skim pages carry the hosts of the pages they were read from.
    @discardableResult
    func add(
        url: URL,
        title: String,
        faviconURL: URL? = nil,
        faviconData: Data? = nil,
        folder folderID: BookmarkFolder.ID? = nil,
        kind: Bookmark.Kind = .page,
        now: Date
    ) -> Bookmark {
        let bookmark = Bookmark(
            url: url, title: title, faviconURL: faviconURL, faviconData: faviconData,
            folderID: folderID, addedAt: now, kind: kind)
        bookmarks.append(bookmark)
        saveIndex()
        return bookmark
    }

    /// The site's icon onto the bookmark: the bytes the list's rows show in place of the
    /// letter tile. They land in the index with the bookmark.
    func setFavicon(_ data: Data, for id: Bookmark.ID) {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        guard bookmarks[i].faviconData != data else { return }
        bookmarks[i].faviconData = data
        saveIndex()
    }

    /// Removes a bookmark.
    func remove(_ id: Bookmark.ID) {
        bookmarks.removeAll { $0.id == id }
        saveIndex()
    }

    /// The bookmarks, newest first.
    var recentlyAdded: [Bookmark] {
        bookmarks.sorted { $0.addedAt > $1.addedAt }
    }

    /// The bookmarks in a folder, newest first.
    func bookmarks(inFolder folderID: BookmarkFolder.ID) -> [Bookmark] {
        bookmarks.filter { $0.folderID == folderID }.sorted { $0.addedAt > $1.addedAt }
    }

    /// How many bookmarks sit in the folder.
    func count(inFolder folderID: BookmarkFolder.ID) -> Int {
        bookmarks.lazy.filter { $0.folderID == folderID }.count
    }

    // MARK: Folders

    /// Makes a folder at the end of the list, taking the next preset tint.
    @discardableResult
    func newFolder(name: String, tint: FolderTint? = nil) -> BookmarkFolder {
        let preset = tint ?? FolderTint.allCases[folders.count % FolderTint.allCases.count]
        let folder = BookmarkFolder(
            name: name, tint: preset, order: (folders.map(\.order).max() ?? -1) + 1)
        folders.append(folder)
        saveIndex()
        return folder
    }

    /// Makes a folder named "New folder", numbered past any that already exist.
    @discardableResult
    func addDefaultFolder() -> BookmarkFolder {
        let base = String(localized: "New folder")
        var name = base
        var suffix = 2
        while folders.contains(where: { $0.name == name }) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        return newFolder(name: name)
    }

    /// Renames a folder.
    func renameFolder(_ id: BookmarkFolder.ID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
        saveIndex()
    }

    /// Moves folders within the list, rewriting the order as it goes.
    func moveFolders(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var ordered = folders
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for index in ordered.indices {
            ordered[index].order = index
        }
        folders = ordered
        saveIndex()
    }

    /// Deletes a folder. Its bookmarks stay, unfiled.
    func removeFolder(_ id: BookmarkFolder.ID) {
        folders.removeAll { $0.id == id }
        for i in bookmarks.indices where bookmarks[i].folderID == id {
            bookmarks[i].folderID = nil
        }
        saveIndex()
    }

    // MARK: Writes

    /// Awaits every write scheduled so far, so tests can look at what was stored.
    func flushWrites() async {
        await indexWrite?.value
    }

    private func saveIndex() {
        guard let persistence else { return }
        let index = BookmarkIndex(bookmarks: bookmarks, folders: folders)
        let previous = indexWrite
        indexWrite = Task { [persistence] in
            await previous?.value
            try? await persistence.saveIndex(index)
        }
    }
}

/// The bookmarks search: titles and addresses, matched the way someone would type.
enum BookmarkSearch {

    /// Whether the bookmark matches the typed query. An empty query matches everything.
    static func matches(_ bookmark: Bookmark, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return [
            bookmark.title, bookmark.url.absoluteString, bookmark.host ?? "",
        ].contains { $0.localizedStandardContains(trimmed) }
    }
}
