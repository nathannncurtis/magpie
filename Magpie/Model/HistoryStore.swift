import Foundation
import Observation

/// One visited page: where it was, what it was called, when it was opened.
struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    typealias ID = UUID

    /// A stable identity across the list and persistence.
    let id: ID
    /// The page's address.
    var url: URL
    /// The page title; empty until the page names itself.
    var title: String
    /// When the page was opened.
    var visitedAt: Date

    init(id: ID = ID(), url: URL, title: String, visitedAt: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
    }

    /// The host without its www prefix, for subtitles and favicon fallbacks.
    var host: String? {
        guard let host = url.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What a row calls the page: its title, or its site while it has none.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (host ?? url.absoluteString) : trimmed
    }
}

/// The saved state of the history store.
struct HistoryIndex: Codable, Equatable, Sendable {
    /// The entries, newest first.
    var entries: [HistoryEntry]
}

/// Where the history store keeps its index.
///
/// Tests use the in-memory implementation; the app uses the file-system one.
protocol HistoryPersistence: Sendable {
    /// The stored index, or nil when nothing has been written yet.
    func loadIndex() async throws -> HistoryIndex?
    /// Replaces the stored index.
    func saveIndex(_ index: HistoryIndex) async throws
}

/// A JSON index in Application Support.
actor FileSystemHistoryPersistence: HistoryPersistence {
    private let indexURL: URL

    /// `directory` overrides the store's home; tests point it at a scratch folder.
    init(directory: URL? = nil) {
        let support =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let home = (directory ?? support)
            .appendingPathComponent("Magpie/HistoryStore", isDirectory: true)
        indexURL = home.appendingPathComponent("history.json")
    }

    func loadIndex() async throws -> HistoryIndex? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return PersistedFile.decode(HistoryIndex.self, from: indexURL, decoder: decoder)
    }

    func saveIndex(_ index: HistoryIndex) async throws {
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
actor InMemoryHistoryPersistence: HistoryPersistence {
    private var index: HistoryIndex?

    init(index: HistoryIndex? = nil) {
        self.index = index
    }

    func loadIndex() async throws -> HistoryIndex? { index }
    func saveIndex(_ index: HistoryIndex) async throws { self.index = index }
}

/// The pages visited in normal tabs, newest first.
///
/// A private tab leaves nothing here. A page opened twice in a row is one entry. The
/// list keeps the last `capacity` visits. Every change schedules a write of the JSON
/// index; all file work happens inside the persistence actor.
@MainActor
@Observable
final class HistoryStore {

    /// The most entries kept; the oldest go first.
    static let capacity = 5000

    /// The entries, newest first.
    private(set) var entries: [HistoryEntry] = []

    private let persistence: HistoryPersistence?
    private let capacity: Int
    private var indexWrite: Task<Void, Never>?

    /// An empty store with nothing behind it.
    init(persistence: HistoryPersistence? = nil, capacity: Int = HistoryStore.capacity) {
        self.persistence = persistence
        self.capacity = capacity
    }

    /// Reads the saved index into this store.
    func loadIndex() async {
        guard let persistence, let index = try? await persistence.loadIndex() else { return }
        entries = Array(index.entries.sorted { $0.visitedAt > $1.visitedAt }.prefix(capacity))
    }

    /// Notes a committed page load. Private tabs and addresses that are not web pages
    /// leave nothing; the same address twice in a row stays one entry.
    func record(url: URL, title: String = "", isPrivate: Bool, now: Date) {
        guard !isPrivate, Self.isWebPage(url) else { return }
        if let newest = entries.first, newest.url == url {
            if !title.isEmpty, newest.title != title {
                entries[0].title = title
                saveIndex()
            }
            return
        }
        entries.insert(HistoryEntry(url: url, title: title, visitedAt: now), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        saveIndex()
    }

    /// The page named itself: its latest entry takes the title. The title comes after the
    /// commit, so it can only land on a page already recorded.
    func updateTitle(_ title: String, for url: URL) {
        guard !title.isEmpty,
            let i = entries.firstIndex(where: { $0.url == url }),
            entries[i].title != title
        else { return }
        entries[i].title = title
        saveIndex()
    }

    /// Removes entries. Returns them as they were, for an undo.
    @discardableResult
    func remove(_ ids: [HistoryEntry.ID]) -> [HistoryEntry] {
        guard !ids.isEmpty else { return [] }
        let gone = Set(ids)
        let removed = entries.filter { gone.contains($0.id) }
        entries.removeAll { gone.contains($0.id) }
        saveIndex()
        return removed
    }

    /// Puts removed entries back where their dates place them.
    func reinstate(_ removed: [HistoryEntry]) {
        let present = Set(entries.map(\.id))
        let returning = removed.filter { !present.contains($0.id) }
        guard !returning.isEmpty else { return }
        entries = Array((entries + returning).sorted { $0.visitedAt > $1.visitedAt }.prefix(capacity))
        saveIndex()
    }

    /// Forgets every visit.
    func clear() {
        entries.removeAll()
        saveIndex()
    }

    /// The entries whose title or site match the query, newest first. An empty query
    /// matches everything.
    func search(_ query: String) -> [HistoryEntry] {
        entries.filter { HistorySearch.matches($0, query: query) }
    }

    private static func isWebPage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: Writes

    /// Awaits every write scheduled so far, so tests can look at what was stored.
    func flushWrites() async {
        await indexWrite?.value
    }

    private func saveIndex() {
        guard let persistence else { return }
        let index = HistoryIndex(entries: entries)
        let previous = indexWrite
        indexWrite = Task { [persistence] in
            await previous?.value
            try? await persistence.saveIndex(index)
        }
    }
}

/// The history search: titles and sites, matched the way someone would type.
enum HistorySearch {

    /// Whether the entry matches the typed query. An empty query matches everything.
    static func matches(_ entry: HistoryEntry, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return [entry.title, entry.host ?? ""].contains { $0.localizedStandardContains(trimmed) }
    }
}
