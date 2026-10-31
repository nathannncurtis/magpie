import CryptoKit
import Foundation
import WebKit

/// A compiled rule list as the compiler hands it back. The payload is a WKContentRuleList in
/// the app; the indirection exists so tests can stand in for WebKit. It is an opaque, immutable
/// token once compiled.
struct CompiledRuleList: @unchecked Sendable {
    let payload: AnyObject

    var contentRuleList: WKContentRuleList? { payload as? WKContentRuleList }
}

/// Compiles rule JSON into rule lists and manages them by identifier. WebKit's implementation
/// persists compiled lists under their identifiers; identifiers carry a content hash here, so
/// unchanged chunks are looked up rather than recompiled.
protocol RuleListCompiler: Sendable {
    func compile(identifier: String, json: String) async throws -> CompiledRuleList
    func ruleList(identifier: String) async -> CompiledRuleList?
    func remove(identifier: String) async
    func availableIdentifiers() async -> [String]
}

/// WebKit's compiler, wrapped for the store. WebKit's store API is main-actor isolated, so
/// these methods are too; the store actor just awaits them.
struct WebKitRuleListCompiler: RuleListCompiler {
    private let storeURL: URL?

    init() {
        self.storeURL = nil
    }

    /// A compiler over a private store; tests use this to avoid touching the app's.
    init(url: URL) {
        self.storeURL = url
    }

    @MainActor private var store: WKContentRuleListStore {
        if let storeURL {
            return WKContentRuleListStore(url: storeURL)
        }
        return WKContentRuleListStore.default()
    }

    @MainActor
    func compile(identifier: String, json: String) async throws -> CompiledRuleList {
        guard
            let list = try await store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            )
        else {
            throw URLError(.cannotParseResponse)
        }
        return CompiledRuleList(payload: list)
    }

    @MainActor
    func ruleList(identifier: String) async -> CompiledRuleList? {
        guard let list = try? await store.contentRuleList(forIdentifier: identifier) else {
            return nil
        }
        return CompiledRuleList(payload: list)
    }

    @MainActor
    func remove(identifier: String) async {
        try? await store.removeContentRuleList(forIdentifier: identifier)
    }

    @MainActor
    func availableIdentifiers() async -> [String] {
        await store.availableIdentifiers() ?? []
    }
}

/// Downloads the filter lists, converts them, stores raw text and converted JSON in Application
/// Support, and keeps compiled rule lists current for each rule set. Downloads use an ephemeral
/// cookieless session with conditional requests; failures keep the last good raw text and
/// compiled lists.
actor FilterListStore {

    /// How long a downloaded list stays fresh; refresh when older.
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// Every identifier this store compiles starts with this, so stale ones can be found among
    /// whatever else lives in the rule list store.
    private static let identifierPrefix = "magpie."

    /// The one-rule probe list the vocabulary detection compiles. It outlives stale cleanup so
    /// it isn't recompiled on every rebuild.
    private static let vocabularyProbeIdentifier = "magpie.vocabulary-probe"

    struct ListRecord: Codable, Sendable, Equatable {
        var etag: String?
        var lastModified: String?
        var lastUpdated: Date?
        /// The resource-type vocabulary the stored conversion was built for.
        var vocabulary: String?
    }

    struct SetRecord: Codable, Sendable, Equatable {
        var identifiers: [String] = []
        var fingerprint: String = ""
    }

    struct PersistedState: Codable, Sendable, Equatable {
        var lists: [String: ListRecord] = [:]
        var sets: [String: SetRecord] = [:]
    }

    private let lists: [FilterList]
    /// The lists mod installs added, fed in by the mod store. Their definitions are not
    /// persisted here: the mod store owns which exist, and feeds them in at every launch.
    private var userLists: [FilterList] = []
    private let directory: URL
    private let session: URLSession
    private let clock: @Sendable () -> Date
    private let compiler: any RuleListCompiler

    private var state = PersistedState()
    private var cache: [String: CompiledRuleList] = [:]
    private var detectedVocabulary: RuleListVocabulary?

    init(
        lists: [FilterList] = FilterList.builtin,
        directory: URL? = nil,
        session: URLSession? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        compiler: (any RuleListCompiler)? = nil
    ) {
        self.lists = lists
        if let directory {
            self.directory = directory
        } else {
            let support =
                FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first ?? FileManager.default.temporaryDirectory
            self.directory = support.appending(component: "FilterLists", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)

        if let session {
            self.session = session
        } else {
            // No cookies, no storage: list downloads must not keep or send anything.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: configuration)
        }
        self.clock = clock
        self.compiler = compiler ?? WebKitRuleListCompiler()
        if let data = try? Data(contentsOf: self.directory.appending(component: "state.json")),
            let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        {
            state = decoded
        }
    }

    // MARK: Refresh

    /// Every list this store knows: the built-ins and whatever the mods added.
    var allLists: [FilterList] {
        lists + userLists
    }

    /// Replaces the mod-installed lists, then brings them in like any other: downloaded
    /// when stale, compiled into the `.mods` set. An empty list leaves the set empty.
    func setUserLists(_ lists: [FilterList]) async {
        guard lists != userLists else { return }
        userLists = lists
        await refreshIfNeeded()
    }

    /// The resource-type vocabulary this WebKit compiles, probed once per session. Which set
    /// is valid depends on the running OS, so it can't be baked into the converted files.
    private func vocabulary() async -> RuleListVocabulary {
        if let detectedVocabulary { return detectedVocabulary }
        let detected: RuleListVocabulary
        do {
            _ = try await compiler.compile(
                identifier: Self.vocabularyProbeIdentifier,
                json: FilterListConverter.vocabularyProbeJSON
            )
            detected = .current
        } catch {
            detected = .legacy
        }
        detectedVocabulary = detected
        return detected
    }

    /// Downloads lists that have never been downloaded or are older than the refresh interval.
    func refreshIfNeeded(now overridden: Date? = nil) async {
        let now = overridden ?? clock()
        let stale = allLists.filter { list in
            guard let updated = state.lists[list.id]?.lastUpdated else { return true }
            return now.timeIntervalSince(updated) >= Self.refreshInterval
        }
        if !stale.isEmpty {
            await download(stale, now: now)
        }
        await rebuildSets()
    }

    /// Downloads every list now, stale or not: the Settings page's "Update now".
    func refreshNow() async {
        await download(allLists, now: clock())
        await rebuildSets()
    }

    private enum DownloadOutcome: Sendable {
        case updated(Data, etag: String?, lastModified: String?)
        case notModified
        case failed
    }

    private func download(_ stale: [FilterList], now: Date) async {
        let priorRecords = state.lists
        let outcomes = await withTaskGroup(
            of: (String, DownloadOutcome).self,
            returning: [String: DownloadOutcome].self
        ) { group in
            for list in stale {
                let record = priorRecords[list.id]
                group.addTask {
                    await self.fetch(list, etag: record?.etag, lastModified: record?.lastModified)
                }
            }
            var collected: [String: DownloadOutcome] = [:]
            for await (id, outcome) in group {
                collected[id] = outcome
            }
            return collected
        }

        for list in stale {
            switch outcomes[list.id] ?? .failed {
            case .failed:
                break
            case .notModified:
                var record = state.lists[list.id] ?? ListRecord()
                record.lastUpdated = now
                state.lists[list.id] = record
            case .updated(let data, let etag, let lastModified):
                let conversion = FilterListConverter.convert(
                    String(decoding: data, as: UTF8.self),
                    vocabulary: await vocabulary()
                )
                // A 200 that converts to nothing (a captive portal page, an emptied file) is
                // a failed update: the last good list stays, and the next refresh retries.
                guard conversion.stats.emitted > 0 else { continue }
                write(data, to: rawURL(for: list))
                if let stored = try? JSONEncoder().encode(StoredFilterRules.from(conversion)) {
                    write(stored, to: convertedURL(for: list))
                }
                state.lists[list.id] = ListRecord(
                    etag: etag,
                    lastModified: lastModified,
                    lastUpdated: now,
                    vocabulary: detectedVocabulary?.rawValue
                )
            }
        }
        persist()
    }

    private func fetch(
        _ list: FilterList,
        etag: String?,
        lastModified: String?
    ) async -> (String, DownloadOutcome) {
        var request = URLRequest(url: list.url)
        request.httpMethod = "GET"
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (list.id, .failed)
            }
            switch http.statusCode {
            case 200:
                return (
                    list.id,
                    .updated(
                        data,
                        etag: http.value(forHTTPHeaderField: "ETag"),
                        lastModified: http.value(forHTTPHeaderField: "Last-Modified")
                    )
                )
            case 304:
                return (list.id, .notModified)
            default:
                return (list.id, .failed)
            }
        } catch {
            return (list.id, .failed)
        }
    }

    // MARK: Set assembly

    /// Rebuilds each rule set from the stored conversions. A set whose raw lists hash to the
    /// fingerprint on record, and whose compiled lists still load, is left alone; otherwise its
    /// chunks are re-encoded and compiled. Identifiers no longer current are removed. A compile
    /// failure leaves the previous set in place.
    private func rebuildSets() async {
        var currentIdentifiers = Set<String>()
        let vocabulary = await self.vocabulary()
        for set in FilterRuleSet.allCases {
            let members = allLists.filter { $0.ruleSet == set }
            guard !members.isEmpty else {
                // With no members the set is gone; drop its record so its compiled
                // lists are cleaned up with the other stale identifiers.
                state.sets[set.rawValue] = nil
                continue
            }
            let fingerprint = Self.fingerprint(of: members, in: directory)

            if let record = state.sets[set.rawValue], !record.identifiers.isEmpty,
                record.fingerprint == fingerprint, await allCached(record.identifiers)
            {
                currentIdentifiers.formUnion(record.identifiers)
                continue
            }

            let conversions = members.compactMap { storedConversion(for: $0, vocabulary: vocabulary) }
            guard !conversions.isEmpty, let encoded = try? encodeChunks(conversions) else { continue }

            do {
                for (index, json) in encoded.enumerated() {
                    let identifier = Self.identifier(for: set, index: index, json: json)
                    currentIdentifiers.insert(identifier)
                    write(Data(json.utf8), to: chunkURL(for: set, index: index))
                    if cache[identifier] != nil { continue }
                    if let found = await compiler.ruleList(identifier: identifier) {
                        cache[identifier] = found
                        continue
                    }
                    cache[identifier] = try await compiler.compile(identifier: identifier, json: json)
                }
                state.sets[set.rawValue] = SetRecord(
                    identifiers: encoded.indices.map {
                        Self.identifier(for: set, index: $0, json: encoded[$0])
                    },
                    fingerprint: fingerprint
                )
            } catch {
                // Keep the last good identifiers and their compiled lists; the next refresh
                // tries again.
                currentIdentifiers.formUnion(state.sets[set.rawValue]?.identifiers ?? [])
            }
        }

        let available = await compiler.availableIdentifiers()
        for identifier in available
        where identifier.hasPrefix(Self.identifierPrefix)
            && !currentIdentifiers.contains(identifier)
            && identifier != Self.vocabularyProbeIdentifier
        {
            await compiler.remove(identifier: identifier)
            cache[identifier] = nil
        }
        persist()
    }

    private func encodeChunks(_ conversions: [FilterListConversion]) throws -> [String] {
        try FilterListConverter.ruleChunks(from: conversions).map {
            try FilterListConverter.encodedJSON($0)
        }
    }

    private func allCached(_ identifiers: [String]) async -> Bool {
        for identifier in identifiers {
            if cache[identifier] != nil { continue }
            guard let found = await compiler.ruleList(identifier: identifier) else { return false }
            cache[identifier] = found
        }
        return true
    }

    /// The compiled rule lists for one set, in chunk order.
    func ruleLists(for set: FilterRuleSet) async -> [CompiledRuleList] {
        var result: [CompiledRuleList] = []
        for identifier in state.sets[set.rawValue]?.identifiers ?? [] {
            if let cached = cache[identifier] {
                result.append(cached)
                continue
            }
            if let found = await compiler.ruleList(identifier: identifier) {
                cache[identifier] = found
                result.append(found)
            }
        }
        return result
    }

    // MARK: Accessors

    /// When a list last refreshed successfully, or nil when it never has.
    func lastUpdated(for list: FilterList) -> Date? {
        state.lists[list.id]?.lastUpdated
    }

    /// Each list with when it last refreshed, for the Settings page.
    func listUpdates() -> [FilterListUpdate] {
        lists.map { list in
            FilterListUpdate(list: list, updated: state.lists[list.id]?.lastUpdated)
        }
    }

    /// The newest successful refresh across the lists, for the Settings row.
    var overallLastUpdated: Date? {
        state.lists.values.compactMap(\.lastUpdated).max()
    }

    /// The raw text of a stored list, for a Settings detail view later.
    func rawText(for list: FilterList) -> String? {
        guard let data = try? Data(contentsOf: rawURL(for: list)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Files and identifiers

    private func rawURL(for list: FilterList) -> URL {
        directory.appending(component: "\(list.id).txt")
    }

    private func convertedURL(for list: FilterList) -> URL {
        directory.appending(component: "\(list.id).json")
    }

    private func chunkURL(for set: FilterRuleSet, index: Int) -> URL {
        directory.appending(component: "set-\(set.rawValue).\(index).json")
    }

    /// `magpie.<set>.<index>.<hash prefix>`; the hash makes an unchanged chunk resolve to the
    /// same identifier WebKit already compiled.
    private static func identifier(for set: FilterRuleSet, index: Int, json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(12)
        return "\(identifierPrefix)\(set.rawValue).\(index).\(hex)"
    }

    /// Hash of the members' raw files; changed when any downloaded content changed.
    private static func fingerprint(of lists: [FilterList], in directory: URL) -> String {
        var input = ""
        for list in lists {
            let url = directory.appending(component: "\(list.id).txt")
            if let data = try? Data(contentsOf: url) {
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                input += "\(list.id):\(digest)\n"
            }
        }
        return String(
            SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        )
    }

    /// The stored conversion for a list, re-converted from the raw text when the WebKit's
    /// vocabulary changed under it (an OS update renaming resource types).
    private func storedConversion(
        for list: FilterList,
        vocabulary: RuleListVocabulary
    ) -> FilterListConversion? {
        let storedVocabulary = state.lists[list.id]?.vocabulary.flatMap {
            RuleListVocabulary(rawValue: $0)
        }
        if storedVocabulary != vocabulary {
            guard let raw = rawText(for: list) else { return nil }
            let conversion = FilterListConverter.convert(raw, vocabulary: vocabulary)
            if let stored = try? JSONEncoder().encode(StoredFilterRules.from(conversion)) {
                write(stored, to: convertedURL(for: list))
            }
            state.lists[list.id]?.vocabulary = vocabulary.rawValue
            persist()
            return conversion
        }
        guard let data = try? Data(contentsOf: convertedURL(for: list)),
            let stored = try? JSONDecoder().decode(StoredFilterRules.self, from: data)
        else { return nil }
        return stored.conversion
    }

    private func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(state) {
            write(data, to: directory.appending(component: "state.json"))
        }
    }
}

extension FilterListStore: RuleSetProviding {
    func refreshStale() async {
        await refreshIfNeeded(now: nil)
    }
}

/// A conversion's rules without stats, as kept in Application Support.
struct StoredFilterRules: Codable, Sendable, Equatable {
    var blocks: [ContentBlockerRule]
    var exceptions: [ContentBlockerRule]

    static func from(_ conversion: FilterListConversion) -> StoredFilterRules {
        StoredFilterRules(blocks: conversion.blockRules, exceptions: conversion.exceptionRules)
    }

    var conversion: FilterListConversion {
        FilterListConversion(blockRules: blocks, exceptionRules: exceptions, stats: FilterListStats())
    }
}
