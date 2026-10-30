import Foundation
import Testing

@testable import Magpie

/// The installed mods: install, enable and disable, remove, update, and the files under
/// them (04 · 06).
@Suite("ModStore")
@MainActor
struct ModsStoreTests {

    private static let listURL =
        URL(string: "https://example.com/l.txt")
        ?? URL(fileURLWithPath: "/list.txt")

    private func draft(
        id: String = "a-mod", kind: ModKind = .userscript, url: URL? = nil
    ) -> ModDraft {
        ModDraft(
            id: id,
            name: "A Mod",
            kind: kind,
            author: "someone",
            version: "1.0",
            summary: nil,
            icon: .linkInstall(),
            source: url.map(ModSource.link) ?? .directory(id),
            script: kind == .userscript ? UserscriptMetadata() : nil,
            scriptBody: kind == .userscript ? "code();" : nil,
            listURL: kind == .filterList ? (url ?? Self.listURL) : nil)
    }

    private func makeStore(io: (any ModStoreIO)? = nil, sink: (any ModListSink)? = nil) -> ModStore {
        ModStore(io: io ?? InMemoryModStoreIO(), listSink: sink)
    }

    @Test("install lands the mod, newest first, running")
    func install() {
        let store = makeStore()
        store.install(draft(id: "one"))
        store.install(draft(id: "two"))

        #expect(store.installedCount == 2)
        #expect(store.mods.map(\.id) == ["two", "one"])
        #expect(store.mod(id: "one")?.enabled == true)
        #expect(store.enabledUserscripts.map(\.id) == ["two", "one"])
    }

    @Test("installing the same mod again keeps its date and state")
    func reinstallKeepsState() async {
        let store = makeStore()
        store.install(draft())
        store.setEnabled(false, id: "a-mod")
        let first = store.mod(id: "a-mod")?.installedAt

        try? await Task.sleep(for: .milliseconds(10))
        var update = draft()
        update.version = "2.0"
        store.install(update)

        let second = store.mod(id: "a-mod")
        #expect(second?.version == "2.0")
        #expect(second?.enabled == false)
        #expect(second?.installedAt == first)
    }

    @Test("off keeps it installed, but it stops running")
    func toggle() {
        let store = makeStore()
        store.install(draft())
        store.setEnabled(false, id: "a-mod")
        #expect(store.mod(id: "a-mod") != nil)
        #expect(store.enabledUserscripts.isEmpty)

        store.setEnabled(true, id: "a-mod")
        #expect(store.enabledUserscripts.map(\.id) == ["a-mod"])
    }

    @Test("remove takes the files with it")
    func remove() {
        let io = InMemoryModStoreIO()
        let store = makeStore(io: io)
        store.install(draft())
        store.storeValue("7", forKey: "n", modID: "a-mod")
        #expect(io.loadBody(for: "a-mod") == "code();")

        store.remove(id: "a-mod")
        #expect(store.mods.isEmpty)
        #expect(io.loadBody(for: "a-mod") == nil)
    }

    @Test("the script's values are kept per mod")
    func values() {
        let store = makeStore()
        store.install(draft(id: "one"))
        store.install(draft(id: "two"))
        store.storeValue("{\"n\":1}", forKey: "n", modID: "one")

        #expect(store.storedValues(modID: "one") == ["n": "{\"n\":1}"])
        #expect(store.storedValues(modID: "two").isEmpty)
        // A value for a mod that is gone is refused.
        store.storeValue("1", forKey: "n", modID: "missing")
        #expect(store.storedValues(modID: "missing").isEmpty)
    }

    @Test("the enabled filter lists reach the blocking store's .mods set")
    func filterListSync() async {
        let sink = RecordingListSink()
        let store = makeStore(sink: sink)

        store.install(draft(id: "list", kind: .filterList))
        store.install(draft(id: "script"))
        await sink.wait()

        #expect(sink.lists.map(\.id) == ["list"])
        #expect(sink.lists.first?.ruleSet == .mods)
        #expect(sink.lists.first?.url == Self.listURL)

        store.setEnabled(false, id: "list")
        await sink.wait()
        #expect(sink.lists.isEmpty)
    }

    @Test("a directory update re-downloads, verifies and replaces")
    func directoryUpdate() async throws {
        let body = """
            // ==UserScript==
            // @name         A Mod
            // @version      2.0
            // @match        *://example.com/*
            // ==/UserScript==
            code();
            """
        let url = try #require(URL(string: "https://mods.example.com/a-mod.user.js"))
        let entry = DirectoryMod(
            id: "a-mod", name: "A Mod", descriptionText: "", author: "someone",
            kind: .userscript, version: "2.0", url: url,
            sha256: ModFetcher.sha256Hex(of: Data(body.utf8)),
            icon: .linkInstall())
        let index = DirectoryIndex(version: 1, mods: [entry])
        let stub = StubModFetch(replies: ["a-mod.user.js": .ok(body)])
        let directory = ModDirectory(
            cache: InMemoryModDirectoryCache.warm(index), fetch: { url in try await stub.call(url) })

        let io = InMemoryModStoreIO()
        let store = makeStore(io: io)
        store.install(draft(id: "a-mod"))
        #expect(store.mod(id: "a-mod")?.version == "1.0")

        let updated = await store.update(id: "a-mod", directory: directory)
        #expect(updated)
        #expect(store.mod(id: "a-mod")?.version == "2.0")
        #expect(io.loadBody(for: "a-mod") == body)
    }

    @Test("a changed file does not update the mod")
    func directoryUpdateRefusesChangedFile() async throws {
        let url = try #require(URL(string: "https://mods.example.com/a-mod.user.js"))
        let entry = DirectoryMod(
            id: "a-mod", name: "A Mod", descriptionText: "", author: "someone",
            kind: .userscript, version: "2.0", url: url,
            sha256: "0000000000000000000000000000000000000000000000000000000000000000",
            icon: .linkInstall())
        let stub = StubModFetch(replies: ["a-mod.user.js": .ok("other bytes")])
        let directory = ModDirectory(
            cache: InMemoryModDirectoryCache.warm(DirectoryIndex(version: 1, mods: [entry])),
            fetch: { url in try await stub.call(url) })

        let store = makeStore()
        store.install(draft(id: "a-mod"))
        let updated = await store.update(id: "a-mod", directory: directory)
        #expect(!updated)
        #expect(store.mod(id: "a-mod")?.version == "1.0")
    }

    @Test("the store keeps its files across a fresh read")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: "mods-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let io = FileSystemModStoreIO(directory: directory)

        let first = makeStore(io: io)
        first.install(draft(id: "one"))
        first.install(draft(id: "list", kind: .filterList))
        first.setEnabled(false, id: "one")
        first.storeValue("\"v\"", forKey: "k", modID: "one")

        let reread = makeStore(io: io)
        #expect(reread.installedCount == 2)
        #expect(reread.mod(id: "one")?.enabled == false)
        #expect(reread.mod(id: "list")?.listURL == Self.listURL)
        #expect(reread.storedValues(modID: "one") == ["k": "\"v\""])
        let one = try #require(reread.mod(id: "one"))
        #expect(reread.scriptBody(for: one) == "code();")
    }
}

/// Records what the store last handed over. The store hands its lists over in a task of
/// its own, so a test meets the next one there.
@MainActor
final class RecordingListSink: ModListSink {

    private(set) var lists: [FilterList] = []
    private var handovers = 0

    func setModLists(_ lists: [FilterList]) async {
        self.lists = lists
        handovers += 1
    }

    /// Waits for the next handover, or a moment past it.
    func wait() async {
        let target = handovers + 1
        for _ in 0..<100 where handovers < target {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
