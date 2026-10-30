import Foundation
import Testing
import WebKit

@testable import Magpie

/// Intercepts every request of a session it's installed in. Tests install a handler keyed to
/// their own hosts; anything unhandled answers 500.
final class BlockingStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func stub(
        _ handler: @escaping @Sendable (URLRequest) -> (Int, [String: String], Data)
    ) {
        lock.withLock { self.handler = handler }
    }

    static var recordedRequests: [URLRequest] {
        lock.withLock { requests }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            requests = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let (status, headers, data) = handler?(request) ?? (500, [:], Data())
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Records what the store asks it to compile, remove and look up.
final class BlockingFakeCompiler: RuleListCompiler, @unchecked Sendable {
    final class FakeRuleList: NSObject {
        let identifier: String
        init(_ identifier: String) { self.identifier = identifier }
    }

    private let lock = NSLock()
    private var compiledIdentifiers: [String] = []
    private var compiledJSONs: [String] = []
    private var removedIdentifiers: [String] = []
    private var available: Set<String> = []
    private var shouldFail = false
    private var rejectsRenamedTypes = false

    func failNextCompiles(_ fail: Bool) {
        lock.withLock { shouldFail = fail }
    }

    /// Rejects any JSON using the renamed resource types, like a WebKit predating the rename.
    func rejectRenamedTypes(_ reject: Bool) {
        lock.withLock { rejectsRenamedTypes = reject }
    }

    var compiled: [String] { lock.withLock { compiledIdentifiers } }
    var compiledJSON: [String] { lock.withLock { compiledJSONs } }
    var removed: [String] { lock.withLock { removedIdentifiers } }

    func compile(identifier: String, json: String) async throws -> CompiledRuleList {
        try lock.withLock {
            if shouldFail || (rejectsRenamedTypes && json.contains("style-sheet")) {
                throw URLError(.cannotDecodeContentData)
            }
            compiledIdentifiers.append(identifier)
            compiledJSONs.append(json)
            available.insert(identifier)
            return CompiledRuleList(payload: FakeRuleList(identifier))
        }
    }

    func ruleList(identifier: String) async -> CompiledRuleList? {
        lock.withLock {
            guard available.contains(identifier) else { return nil }
            return CompiledRuleList(payload: FakeRuleList(identifier))
        }
    }

    func remove(identifier: String) async {
        lock.withLock {
            available.remove(identifier)
            removedIdentifiers.append(identifier)
        }
    }

    func availableIdentifiers() async -> [String] {
        lock.withLock { Array(available) }
    }
}

/// A settable clock, so a test can advance time between refreshes.
private final class BlockingClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@Suite("FilterListStore", .serialized)
struct BlockingStoreTests {

    private static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    private static func list(
        id: String,
        url rawURL: String,
        ruleSet: FilterRuleSet
    ) -> FilterList {
        guard let url = URL(string: rawURL) else {
            preconditionFailure("Test list URL is not a URL: \(rawURL)")
        }
        return FilterList(id: id, title: id, url: url, ruleSet: ruleSet)
    }

    private static let adsBody = "[Adblock Plus 2.0]\n||ads.one^\n##.banner\n"
    private static let cookiesBody = "[Adblock Plus 2.0]\n||cookie.two^\n"

    /// Compiled identifiers without the store's vocabulary probe, which every first refresh
    /// also compiles.
    private func chunks(_ identifiers: [String]) -> [String] {
        identifiers.filter { !$0.hasPrefix("magpie.vocabulary") }
    }

    private func makeStore(
        lists: [FilterList],
        compiler: BlockingFakeCompiler,
        clock: BlockingClock
    ) -> FilterListStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockingStubURLProtocol.self]
        configuration.urlCache = nil
        let directory = FileManager.default.temporaryDirectory.appending(
            component: UUID().uuidString,
            directoryHint: .isDirectory
        )
        return FilterListStore(
            lists: lists,
            directory: directory,
            session: URLSession(configuration: configuration),
            clock: { clock.now },
            compiler: compiler
        )
    }

    private func stubBodies(_ bodies: [String: String], etag: String = "v1") {
        BlockingStubURLProtocol.stub { request in
            guard let url = request.url, let body = bodies[url.absoluteString] else {
                return (500, [:], Data())
            }
            if request.value(forHTTPHeaderField: "If-None-Match") == etag {
                return (304, [:], Data())
            }
            return (
                200,
                ["ETag": etag, "Last-Modified": "Wed, 29 Oct 2026 10:00:00 GMT"],
                Data(body.utf8)
            )
        }
    }

    @Test("first run downloads everything, converts, compiles and records timestamps")
    func firstRun() async {
        BlockingStubURLProtocol.reset()
        let compiler = BlockingFakeCompiler()
        let ads = Self.list(id: "one", url: "https://one.example/filters.txt", ruleSet: .adsAndTrackers)
        let cookies = Self.list(id: "two", url: "https://two.example/filters.txt", ruleSet: .cookieBanners)
        let store = makeStore(
            lists: [ads, cookies],
            compiler: compiler,
            clock: BlockingClock(Self.epoch)
        )
        stubBodies([
            ads.url.absoluteString: Self.adsBody,
            cookies.url.absoluteString: Self.cookiesBody,
        ])

        await store.refreshIfNeeded()

        #expect(BlockingStubURLProtocol.recordedRequests.count == 2)
        let compiledChunks = chunks(compiler.compiled)
        #expect(compiledChunks.count == 2)
        #expect(
            compiledChunks.allSatisfy {
                $0.hasPrefix("magpie.adsAndTrackers.0.") || $0.hasPrefix("magpie.cookieBanners.0.")
            }
        )
        #expect(await store.ruleLists(for: .adsAndTrackers).count == 1)
        #expect(await store.ruleLists(for: .cookieBanners).count == 1)
        #expect(await store.lastUpdated(for: ads) == Self.epoch)
        #expect(await store.overallLastUpdated == Self.epoch)
        #expect(await store.rawText(for: ads) == Self.adsBody)
    }

    @Test("a fresh refresh sends no requests")
    func freshRefreshIsQuiet() async {
        BlockingStubURLProtocol.reset()
        let compiler = BlockingFakeCompiler()
        let ads = Self.list(id: "one", url: "https://one.example/filters.txt", ruleSet: .adsAndTrackers)
        let store = makeStore(
            lists: [ads],
            compiler: compiler,
            clock: BlockingClock(Self.epoch)
        )
        stubBodies([ads.url.absoluteString: Self.adsBody])
        await store.refreshIfNeeded()
        let afterFirst = BlockingStubURLProtocol.recordedRequests.count
        #expect(afterFirst == 1)

        await store.refreshIfNeeded(now: Self.epoch.addingTimeInterval(60 * 60))
        #expect(BlockingStubURLProtocol.recordedRequests.count == afterFirst)
        #expect(compiler.compiled.count == 2)
    }

    @Test("an older-than-24 h refresh sends conditional requests and honours 304")
    func conditionalRefresh() async {
        BlockingStubURLProtocol.reset()
        let compiler = BlockingFakeCompiler()
        let clock = BlockingClock(Self.epoch)
        let ads = Self.list(id: "one", url: "https://one.example/filters.txt", ruleSet: .adsAndTrackers)
        let store = makeStore(lists: [ads], compiler: compiler, clock: clock)
        stubBodies([ads.url.absoluteString: Self.adsBody])
        await store.refreshIfNeeded()
        let compiledAfterFirst = compiler.compiled.count
        let rawAfterFirst = await store.rawText(for: ads)

        clock.now = Self.epoch.addingTimeInterval(FilterListStore.refreshInterval + 60)
        await store.refreshIfNeeded()

        let requests = BlockingStubURLProtocol.recordedRequests
        #expect(requests.count == 2)
        #expect(requests.last?.value(forHTTPHeaderField: "If-None-Match") == "v1")
        #expect(
            requests.last?.value(forHTTPHeaderField: "If-Modified-Since")
                == "Wed, 29 Oct 2026 10:00:00 GMT"
        )
        #expect(compiler.compiled.count == compiledAfterFirst)
        #expect(await store.rawText(for: ads) == rawAfterFirst)
        #expect(await store.lastUpdated(for: ads) == clock.now)
    }

    @Test("changed content compiles new identifiers and removes the stale ones")
    func contentChange() async {
        BlockingStubURLProtocol.reset()
        let compiler = BlockingFakeCompiler()
        let clock = BlockingClock(Self.epoch)
        let ads = Self.list(id: "one", url: "https://one.example/filters.txt", ruleSet: .adsAndTrackers)
        let store = makeStore(lists: [ads], compiler: compiler, clock: clock)
        stubBodies([ads.url.absoluteString: Self.adsBody])
        await store.refreshIfNeeded()
        let firstIdentifiers = chunks(compiler.compiled)
        #expect(firstIdentifiers.count == 1)

        clock.now = Self.epoch.addingTimeInterval(FilterListStore.refreshInterval + 60)
        stubBodies([ads.url.absoluteString: Self.adsBody + "||added.later^\n"])
        await store.refreshIfNeeded()

        #expect(chunks(compiler.compiled).count == 2)
        #expect(chunks(compiler.compiled).first == firstIdentifiers.first)
        #expect(compiler.removed == firstIdentifiers)
        #expect(await store.ruleLists(for: .adsAndTrackers).count == 1)
    }

    @Test("a failed download keeps the last good raw text and compiled lists")
    func failureKeepsLastGood() async {
        BlockingStubURLProtocol.reset()
        let compiler = BlockingFakeCompiler()
        let clock = BlockingClock(Self.epoch)
        let ads = Self.list(id: "one", url: "https://one.example/filters.txt", ruleSet: .adsAndTrackers)
        let store = makeStore(lists: [ads], compiler: compiler, clock: clock)
        stubBodies([ads.url.absoluteString: Self.adsBody])
        await store.refreshIfNeeded()
        let compiledBefore = compiler.compiled
        let rawBefore = await store.rawText(for: ads)

        clock.now = Self.epoch.addingTimeInterval(FilterListStore.refreshInterval + 60)
        BlockingStubURLProtocol.stub { _ in (500, [:], Data()) }
        await store.refreshIfNeeded()

        #expect(compiler.compiled == compiledBefore)
        #expect(compiler.removed.isEmpty)
        #expect(await store.rawText(for: ads) == rawBefore)
        #expect(await store.lastUpdated(for: ads) == Self.epoch)
        #expect(await store.ruleLists(for: .adsAndTrackers).count == 1)
    }

    @Test("a failed compile keeps the previous set in place")
    func compileFailureKeepsPrevious() async {
        BlockingStubURLProtocol.reset()
        let compiler = BlockingFakeCompiler()
        let clock = BlockingClock(Self.epoch)
        let ads = Self.list(id: "one", url: "https://one.example/filters.txt", ruleSet: .adsAndTrackers)
        let store = makeStore(lists: [ads], compiler: compiler, clock: clock)
        stubBodies([ads.url.absoluteString: Self.adsBody])
        await store.refreshIfNeeded()
        let firstIdentifiers = chunks(compiler.compiled)
        #expect(firstIdentifiers.count == 1)

        compiler.failNextCompiles(true)
        clock.now = Self.epoch.addingTimeInterval(FilterListStore.refreshInterval + 60)
        stubBodies([ads.url.absoluteString: Self.adsBody + "||added.later^\n"])
        await store.refreshIfNeeded()

        #expect(await store.ruleLists(for: .adsAndTrackers).count == firstIdentifiers.count)
        #expect(compiler.removed.isEmpty)
    }

    @Test("a WebKit that rejects the renamed types still gets compilable rules")
    func legacyVocabularyFallback() async {
        BlockingStubURLProtocol.reset()
        let compiler = BlockingFakeCompiler()
        compiler.rejectRenamedTypes(true)
        let ads = Self.list(id: "one", url: "https://one.example/filters.txt", ruleSet: .adsAndTrackers)
        let store = makeStore(
            lists: [ads],
            compiler: compiler,
            clock: BlockingClock(Self.epoch)
        )
        stubBodies([ads.url.absoluteString: "[Adblock Plus 2.0]\n||ads.one^$stylesheet\n"])

        await store.refreshIfNeeded()

        let compiledChunks = chunks(compiler.compiled)
        #expect(compiledChunks.count == 1)
        #expect(compiler.compiledJSON.contains { $0.contains("\"stylesheet\"") })
        #expect(compiler.compiledJSON.allSatisfy { !$0.contains("style-sheet") })
        #expect(await store.ruleLists(for: .adsAndTrackers).count == 1)
    }

    @Test("WebKit compiles a converted rule list for real")
    func realCompilation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)
        let compiler = WebKitRuleListCompiler(url: directory)

        // The probe decides which resource-type names this WebKit takes.
        let vocabulary: RuleListVocabulary
        do {
            _ = try await compiler.compile(
                identifier: "magpie.test.probe",
                json: FilterListConverter.vocabularyProbeJSON
            )
            vocabulary = .current
        } catch {
            vocabulary = .legacy
        }

        let conversion = FilterListConverter.convert(
            """
            [Adblock Plus 2.0]
            ||ads.example.com^$script,stylesheet,subdocument
            ##.ad
            ##.promo
            example.com##div.banner > a
            @@||fine.example^$document
            """,
            vocabulary: vocabulary
        )
        let chunk = try #require(FilterListConverter.ruleChunks(from: [conversion]).first)
        let json = try FilterListConverter.encodedJSON(chunk)

        let identifier = "magpie.test.0.\(UUID().uuidString.prefix(12).lowercased())"
        let compiled = try await compiler.compile(identifier: identifier, json: json)
        #expect(compiled.contentRuleList != nil)
        let lookedUp = await compiler.ruleList(identifier: identifier)
        #expect(lookedUp?.contentRuleList != nil)
    }
}
