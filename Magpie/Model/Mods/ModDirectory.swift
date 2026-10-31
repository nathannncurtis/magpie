import Foundation
import Observation

/// One mod in the directory index.
///
/// The index is a JSON document in a public repository, added to only through reviewed
/// pull requests (04 · 06). Each entry carries everything the app needs to show the mod
/// and to check what it downloads:
///
/// ```json
/// {
///   "id": "google-answer-box",
///   "name": "Google Answer Box",
///   "description": "Pins the direct answer above the noise.",
///   "author": "nathannncurtis",
///   "type": "userscript",
///   "version": "1.3",
///   "url": "https://raw.githubusercontent.com/nathannncurtis/magpie-mods/main/scripts/google-answer-box.user.js",
///   "sha256": "the lowercase hex digest of the file the url serves",
///   "icon": { "glyph": "an SF Symbol name", "gradient": ["#4C8DF6", "#1A56D6"] },
///   "featured": true,
///   "preview": "googleAnswerBox",
///   "popularRank": 1
/// }
/// ```
///
/// `type` is `"userscript"` or `"filterList"`. `featured`, `preview` and `popularRank`
/// are optional: `preview` names what the featured card draws, and `popularRank` is the
/// mod's place in "Popular this week", counted from 1.
struct DirectoryMod: Identifiable, Codable, Equatable, Sendable {

    /// What the featured card draws for this mod.
    enum PreviewKind: String, Codable, Equatable, Sendable {
        /// The drawn mini search result with the answer card ringed (board 06).
        case googleAnswerBox
    }

    let id: String
    let name: String
    let descriptionText: String
    let author: String
    let kind: ModKind
    let version: String
    let url: URL
    let sha256: String
    let icon: ModIconSpec
    var featured: Bool?
    var preview: PreviewKind?
    var popularRank: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, descriptionText = "description", author
        case kind = "type"
        case version, url, sha256, icon, featured, preview, popularRank
    }

    /// The entry's file, verified against the digest the index carries.
    func download(fetch: @Sendable (URL) async throws -> ModDownload) async throws -> String {
        guard isWellFormed else { throw DirectoryError.unreachable }
        let downloaded = try await fetch(url)
        guard downloaded.response.statusCode == 200, ModFetcher.isWithinLimit(downloaded) else {
            throw DirectoryError.unreachable
        }
        guard ModFetcher.sha256Hex(of: downloaded.data) == sha256.lowercased() else {
            throw DirectoryError.changedFile
        }
        return String(decoding: downloaded.data, as: UTF8.self)
    }

    /// The entry as a draft, once its file is in hand. A script file that no longer
    /// parses is refused: nothing is installed from it.
    func draft(body: String) -> ModDraft? {
        guard isWellFormed else { return nil }
        switch kind {
        case .userscript:
            guard let script = Userscript.parse(body), script.metadata.hasRunRules else {
                return nil
            }
            return ModDraft(
                id: id,
                name: name,
                kind: .userscript,
                author: author,
                version: version,
                summary: descriptionText,
                icon: icon,
                source: .directory(id),
                script: script.metadata,
                scriptBody: script.body,
                listURL: nil)
        case .filterList:
            return ModDraft(
                id: id,
                name: name,
                kind: .filterList,
                author: author,
                version: version,
                summary: descriptionText,
                icon: icon,
                source: .directory(id),
                script: nil,
                scriptBody: nil,
                listURL: url)
        }
    }

    /// Whether the entry is safe to act on: its id names a file and a content world, so
    /// it is plain lowercase letters, digits and dashes; its file comes over https; and
    /// its digest is a full SHA-256.
    var isWellFormed: Bool {
        let idCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let digestCharacters = Set("0123456789abcdef")
        return !id.isEmpty && id.count <= 64 && id.allSatisfy(idCharacters.contains)
            && !id.hasPrefix("link-")
            && ModFetcher.isSecure(url)
            && sha256.count == 64 && sha256.lowercased().allSatisfy(digestCharacters.contains)
    }

    enum DirectoryError: Error, Equatable {
        case unreachable
        case changedFile
    }
}

/// The whole index, decoded.
struct DirectoryIndex: Codable, Equatable, Sendable {

    let version: Int
    let mods: [DirectoryMod]

    /// The one featured mod, if the index names one.
    var featured: DirectoryMod? {
        mods.first { $0.featured == true }
    }

    /// "Popular this week", best place first, leaving out anything unranked.
    var popular: [DirectoryMod] {
        mods
            .filter { ($0.popularRank ?? 0) > 0 }
            .sorted {
                ($0.popularRank ?? Int.max) < ($1.popularRank ?? Int.max)
            }
    }

    func entry(id: String) -> DirectoryMod? {
        mods.first { $0.id == id }
    }
}

/// The mod directory: an index fetched from its repository at most once a day, kept
/// cached, and shown quietly as whatever it last had when the repository can't be
/// reached (04 · 06).
@MainActor
@Observable
final class ModDirectory {

    /// Where the index lives. The repository is public and additions are reviewed.
    static let indexURL: URL = {
        guard
            let url = URL(
                string: "https://raw.githubusercontent.com/nathannncurtis/magpie-mods/main/index.json")
        else {
            preconditionFailure("The directory index address is not a URL")
        }
        return url
    }()

    /// How long a fetched index stays fresh; refresh when older.
    nonisolated static let refreshInterval: TimeInterval = 24 * 60 * 60

    private(set) var mods: [DirectoryMod] = []
    private(set) var featured: DirectoryMod?
    private(set) var popular: [DirectoryMod] = []

    private let cache: ModDirectoryCache
    private let clock: @Sendable () -> Date
    private let fetch: @Sendable (URL) async throws -> ModDownload

    init(
        cache: ModDirectoryCache = FileSystemModDirectoryCache(),
        clock: @escaping @Sendable () -> Date = { Date() },
        fetch: @escaping @Sendable (URL) async throws -> ModDownload = ModFetcher.live
    ) {
        self.cache = cache
        self.clock = clock
        self.fetch = fetch
        adopt(cache.loadIndex())
    }

    /// Brings the index in: the cache first, then a fetch when it is a day old. A fetch
    /// that fails leaves whatever was already there.
    func refresh() async {
        let now = clock()
        if cache.loadState().isFresh(asOf: now) { return }
        do {
            let downloaded = try await fetch(Self.indexURL)
            guard downloaded.response.statusCode == 200 else { return }
            let index = try Self.decode(downloaded.data)
            cache.save(index: index, fetchedAt: now)
            adopt(index)
        } catch {
            // Keep the cached index; an empty directory stays empty.
        }
    }

    /// One entry's file, verified against the index's digest.
    func download(_ entry: DirectoryMod) async throws -> String {
        try await entry.download(fetch: fetch)
    }

    func entry(id: String) -> DirectoryMod? {
        mods.first { $0.id == id }
    }

    private func adopt(_ index: DirectoryIndex?) {
        guard let index else { return }
        mods = index.mods
        featured = index.featured
        popular = index.popular
    }

    private static func decode(_ data: Data) throws -> DirectoryIndex {
        try JSONDecoder().decode(DirectoryIndex.self, from: data)
    }
}

/// Where the directory keeps its cached index and when it last fetched it.
protocol ModDirectoryCache: Sendable {
    func loadIndex() -> DirectoryIndex?
    func loadState() -> ModDirectoryCacheState
    func save(index: DirectoryIndex, fetchedAt: Date)
}

struct ModDirectoryCacheState: Codable, Equatable, Sendable {
    var fetchedAt: Date?

    /// Fresh within the refresh interval, counting a cache with no fetch as stale.
    func isFresh(asOf now: Date) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) < ModDirectory.refreshInterval
    }
}

/// The cache in Application Support: the index JSON and a small state file beside it.
struct FileSystemModDirectoryCache: ModDirectoryCache {

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support =
                FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first ?? FileManager.default.temporaryDirectory
            self.directory = support.appending(component: "Mods", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func loadIndex() -> DirectoryIndex? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DirectoryIndex.self, from: data)
    }

    func loadState() -> ModDirectoryCacheState {
        guard
            let data = try? Data(contentsOf: stateURL),
            let state = try? JSONDecoder().decode(ModDirectoryCacheState.self, from: data)
        else { return ModDirectoryCacheState() }
        return state
    }

    func save(index: DirectoryIndex, fetchedAt: Date) {
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: fileURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(ModDirectoryCacheState(fetchedAt: fetchedAt)) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private var fileURL: URL {
        directory.appending(component: "directory-index.json")
    }

    private var stateURL: URL {
        directory.appending(component: "directory-state.json")
    }
}

/// A cache held in memory, for tests and UI runs.
final class InMemoryModDirectoryCache: ModDirectoryCache, @unchecked Sendable {

    private let lock = NSLock()
    private var index: DirectoryIndex?
    private var state = ModDirectoryCacheState()

    func loadIndex() -> DirectoryIndex? {
        lock.withLock { index }
    }

    func loadState() -> ModDirectoryCacheState {
        lock.withLock { state }
    }

    func save(index: DirectoryIndex, fetchedAt: Date) {
        lock.withLock {
            self.index = index
            self.state = ModDirectoryCacheState(fetchedAt: fetchedAt)
        }
    }

    /// A cache that starts with a given index, already fresh.
    static func warm(_ index: DirectoryIndex?) -> InMemoryModDirectoryCache {
        let cache = InMemoryModDirectoryCache()
        if let index {
            cache.save(index: index, fetchedAt: Date())
        }
        return cache
    }
}
