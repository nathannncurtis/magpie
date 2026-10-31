import Foundation
import Observation

/// What kind of mod it is.
enum ModKind: String, Codable, Equatable, Sendable {
    case userscript
    case filterList
}

/// A mod's icon: a white glyph on a two-colour, 160-degree gradient tile. Directory mods
/// carry theirs in the index; a link install gets a plain one.
struct ModIconSpec: Codable, Equatable, Hashable, Sendable {

    /// An SF Symbol name.
    var glyph: String
    /// The gradient's two colours, as "#RRGGBB".
    var gradient: [String]

    /// The plain icon a link install gets.
    static func linkInstall(glyph: String = "chevron.left.forwardslash.chevron.right") -> ModIconSpec {
        ModIconSpec(glyph: glyph, gradient: ["#9AA3AE", "#5D6670"])
    }
}

/// Where an installed mod came from.
enum ModSource: Codable, Equatable, Sendable {
    /// A directory entry, by its id.
    case directory(String)
    /// A link the user pasted.
    case link(URL)

    /// The mod's own address, wherever it came from.
    var url: URL? {
        switch self {
        case .directory: return nil
        case .link(let url): return url
        }
    }
}

/// One installed mod: what it is, where it came from, and whether it runs.
struct InstalledMod: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: ModKind
    var author: String?
    var version: String?
    var summary: String?
    var icon: ModIconSpec
    var enabled: Bool
    var installedAt: Date
    var source: ModSource
    /// The userscript's metadata, for script mods. The code itself stays in its file.
    var script: UserscriptMetadata?
    /// The list's address, for filter-list mods; the blocking store downloads by it.
    var listURL: URL?
}

/// A mod ready to install, built either from a directory entry or from a link.
struct ModDraft {
    var id: String
    var name: String
    var kind: ModKind
    var author: String?
    var version: String?
    var summary: String?
    var icon: ModIconSpec
    var source: ModSource
    var script: UserscriptMetadata?
    var scriptBody: String?
    var listURL: URL?
}

/// What mod-installed filter lists plug into: the blocking store's `.mods` set, applied
/// to every page while any filter-list mod is enabled (04 · 06).
@MainActor
protocol ModListSink: AnyObject {
    func setModLists(_ lists: [FilterList]) async
}

/// Where the mod store keeps its index, its script files and the GM shim's values. The
/// app writes to Application Support; tests keep everything in memory.
protocol ModStoreIO: Sendable {
    func loadMods() -> [InstalledMod]
    func save(mods: [InstalledMod])
    func write(body: String, for id: String)
    func loadBody(for id: String) -> String?
    func deleteBody(for id: String)
    func loadValues(modID: String) -> [String: String]
    func save(values: [String: String], modID: String)
}

/// The app's own files: Application Support/Mods.
struct FileSystemModStoreIO: ModStoreIO {

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
        try? FileManager.default.createDirectory(
            at: valuesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func loadMods() -> [InstalledMod] {
        PersistedFile.decode([InstalledMod].self, from: directory.appending(component: "mods.json"))
            ?? []
    }

    func save(mods: [InstalledMod]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(mods) {
            try? data.write(to: directory.appending(component: "mods.json"), options: .atomic)
        }
    }

    func write(body: String, for id: String) {
        try? Data(body.utf8).write(to: bodyURL(for: id), options: .atomic)
    }

    func loadBody(for id: String) -> String? {
        guard let data = try? Data(contentsOf: bodyURL(for: id)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func deleteBody(for id: String) {
        try? FileManager.default.removeItem(at: bodyURL(for: id))
    }

    func loadValues(modID: String) -> [String: String] {
        PersistedFile.decode([String: String].self, from: valuesURL(for: modID)) ?? [:]
    }

    func save(values: [String: String], modID: String) {
        if let data = try? JSONEncoder().encode(values) {
            try? data.write(to: valuesURL(for: modID), options: .atomic)
        }
    }

    private var valuesDirectory: URL {
        directory.appending(component: "values", directoryHint: .isDirectory)
    }

    private func bodyURL(for id: String) -> URL {
        directory.appending(component: "\(id).user.js")
    }

    private func valuesURL(for modID: String) -> URL {
        valuesDirectory.appending(component: "\(modID).json")
    }
}

/// Everything in memory, for tests and UI runs that must not touch the app's files.
final class InMemoryModStoreIO: ModStoreIO, @unchecked Sendable {

    private let lock = NSLock()
    private var mods: [InstalledMod] = []
    private var bodies: [String: String] = [:]
    private var values: [String: [String: String]] = [:]

    func loadMods() -> [InstalledMod] {
        lock.withLock { mods }
    }

    func save(mods: [InstalledMod]) {
        lock.withLock { self.mods = mods }
    }

    func write(body: String, for id: String) {
        lock.withLock { bodies[id] = body }
    }

    func loadBody(for id: String) -> String? {
        lock.withLock { bodies[id] }
    }

    func deleteBody(for id: String) {
        lock.withLock { bodies[id] = nil }
    }

    func loadValues(modID: String) -> [String: String] {
        lock.withLock { values[modID] ?? [:] }
    }

    func save(values: [String: String], modID: String) {
        lock.withLock { self.values[modID] = values }
    }
}

/// The installed mods: install, enable and disable, remove, update (04 · 06). Every
/// change persists at once and tells the injector and the blocking store what changed.
@MainActor
@Observable
final class ModStore {

    /// Every installed mod, newest install first.
    private(set) var mods: [InstalledMod]

    /// Called with the enabled userscript mods after every change, so the injector can
    /// re-apply them. Pages already showing a document keep running what they had.
    var onUserscriptsChanged: (@MainActor ([InstalledMod]) -> Void)?

    private let io: any ModStoreIO
    private let listSink: (any ModListSink)?

    init(io: any ModStoreIO = FileSystemModStoreIO(), listSink: (any ModListSink)? = nil) {
        self.io = io
        self.listSink = listSink
        self.mods = io.loadMods().sorted { $0.installedAt > $1.installedAt }
        if !mods.isEmpty {
            Task { await self.syncFilterLists() }
        }
    }

    // MARK: Reading

    var installedCount: Int { mods.count }

    /// The userscripts to inject: enabled script mods, newest first.
    var enabledUserscripts: [InstalledMod] {
        mods.filter { $0.enabled && $0.kind == .userscript }
    }

    func mod(id: String) -> InstalledMod? {
        mods.first { $0.id == id }
    }

    /// The mod's code, read back from its file.
    func scriptBody(for mod: InstalledMod) -> String? {
        io.loadBody(for: mod.id)
    }

    // MARK: Installing

    /// Installs a mod. Installing the same one again updates it in place, keeping its
    /// install date and enabled state.
    @discardableResult
    func install(_ draft: ModDraft) -> InstalledMod {
        let mod = InstalledMod(draft: draft, existing: mod(id: draft.id))
        if let body = draft.scriptBody {
            io.write(body: body, for: mod.id)
        }
        mods.removeAll { $0.id == mod.id }
        mods.insert(mod, at: 0)
        mods.sort { $0.installedAt > $1.installedAt }
        changed()
        return mod
    }

    /// Enables or disables a mod. Off keeps it installed, but it stops running.
    func setEnabled(_ enabled: Bool, id: String) {
        guard let index = mods.firstIndex(where: { $0.id == id }) else { return }
        guard mods[index].enabled != enabled else { return }
        mods[index].enabled = enabled
        changed()
    }

    /// Removes a mod, with its files.
    func remove(id: String) {
        guard mods.contains(where: { $0.id == id }) else { return }
        mods.removeAll { $0.id == id }
        io.deleteBody(for: id)
        changed()
    }

    // MARK: Updating

    /// Re-downloads a mod from where it came and replaces what it keeps: the code for a
    /// script, the metadata it carries, and the version. A download that fails, that no
    /// longer verifies, or that turned into something else leaves the mod as it was.
    @discardableResult
    func update(
        id: String,
        directory: ModDirectory,
        now: Date = Date(),
        fetch: @Sendable (URL) async throws -> ModDownload = ModFetcher.live
    ) async -> Bool {
        guard let current = mod(id: id) else { return false }

        let draft: ModDraft
        switch current.source {
        case .directory(let entryID):
            guard
                let entry = directory.entry(id: entryID),
                let body = try? await directory.download(entry),
                let built = entry.draft(body: body)
            else { return false }
            draft = built
        case .link(let url):
            guard let fetched = await ModLinkInstaller.fetchDraft(from: url, fetch: fetch) else {
                return false
            }
            guard fetched.kind == current.kind else { return false }
            draft = fetched
        }

        var updated = draft.installedMod(existing: current)
        updated.enabled = current.enabled
        if let body = draft.scriptBody {
            io.write(body: body, for: updated.id)
        }
        guard let index = mods.firstIndex(where: { $0.id == id }) else { return false }
        mods[index] = updated
        changed()
        return true
    }

    // MARK: Script values (the GM shim's storage)

    /// The values a mod has saved for itself, each value as the JSON the script handed
    /// over. They are injected with the script, so `GM_getValue` reads them.
    func storedValues(modID: String) -> [String: String] {
        io.loadValues(modID: modID)
    }

    /// One value the shim relayed from the page.
    func storeValue(_ json: String, forKey key: String, modID: String) {
        guard let mod = mod(id: modID) else { return }
        var values = io.loadValues(modID: modID)
        values[key] = json
        io.save(values: values, modID: mod.id)
    }

    // MARK: Wiring

    private func changed() {
        persist()
        Task { await self.syncFilterLists() }
        onUserscriptsChanged?(enabledUserscripts)
    }

    private func persist() {
        io.save(mods: mods)
    }

    /// Hands the enabled filter-list mods to the blocking store, which compiles them
    /// into the `.mods` rule set. An empty list clears the set.
    private func syncFilterLists() async {
        guard let listSink else { return }
        let lists =
            mods
            .filter { $0.enabled && $0.kind == .filterList }
            .compactMap { mod -> FilterList? in
                guard let url = mod.listURL else { return nil }
                return FilterList.userAdded(id: mod.id, title: mod.name, url: url)
            }
        await listSink.setModLists(lists)
    }
}

extension ContentBlocker: ModListSink {}

extension InstalledMod {
    /// A draft's record, keeping what the installed mod already had.
    fileprivate init(draft: ModDraft, existing: InstalledMod?) {
        self.init(
            id: draft.id,
            name: draft.name,
            kind: draft.kind,
            author: draft.author,
            version: draft.version,
            summary: draft.summary,
            icon: draft.icon,
            enabled: existing?.enabled ?? true,
            installedAt: existing?.installedAt ?? Date(),
            source: draft.source,
            script: draft.script,
            listURL: draft.listURL)
    }

    fileprivate init(draft: ModDraft) {
        self.init(draft: draft, existing: nil)
    }
}

extension ModDraft {
    /// The draft as an installed record, carrying over the replaced mod's dates and state.
    fileprivate func installedMod(existing: InstalledMod) -> InstalledMod {
        InstalledMod(draft: self, existing: existing)
    }
}
