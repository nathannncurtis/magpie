import Foundation
import Testing

@testable import Magpie

@Suite("Tab persistence")
struct TabPersistenceTests {

    @Test("the store round-trips through the in-memory persistence")
    @MainActor
    func inMemoryRoundTrip() async {
        let persistence = InMemoryTabPersistence()
        let store = TabStore(persistence: persistence)
        let a = store.newTab(url: URL(string: "https://a.example"), title: "A", now: Date(timeIntervalSince1970: 100))
        let b = store.newTab(
            url: URL(string: "https://b.example/page"),
            title: "B",
            faviconURL: URL(string: "https://b.example/icon.png"),
            now: Date(timeIntervalSince1970: 200))
        store.setSnapshot(Data([9, 9]), for: a.id)
        store.close(b.id)
        await store.flushWrites()

        let reopened = await TabStore.open(persistence: persistence)
        #expect(reopened.tabs.map(\.id) == [a.id])
        #expect(reopened.currentTabID == a.id)
        #expect(reopened.tabs.first?.title == "A")
        #expect(reopened.tabs.first?.lastActive == Date(timeIntervalSince1970: 100))
        #expect(reopened.tabs.first?.snapshot == nil)

        let snapshot = await reopened.loadSnapshot(for: a.id)
        #expect(snapshot == Data([9, 9]))
        #expect(reopened.tabs.first?.snapshot == Data([9, 9]))
    }

    @Test("an empty archive round-trips")
    @MainActor
    func emptyRoundTrip() async {
        let persistence = InMemoryTabPersistence()
        let reopened = await TabStore.open(persistence: persistence)
        #expect(reopened.tabs.isEmpty)
        #expect(reopened.currentTabID == nil)
        #expect(reopened.archivedTabs.isEmpty)
    }

    @Test("a saved current tab that is gone falls back to the first tab")
    @MainActor
    func danglingCurrentFallsBack() async {
        let tab = Tab(title: "Only", lastActive: Date(timeIntervalSince1970: 1))
        let index = TabIndex(openTabs: [tab], currentTabID: Tab.ID(), archivedTabs: [])
        let persistence = InMemoryTabPersistence(index: index)

        let reopened = await TabStore.open(persistence: persistence)

        #expect(reopened.currentTabID == tab.id)
    }

    @Test("the index and snapshots round-trip through files")
    func fileSystemRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileSystemTabPersistence(directory: directory)

        var tab = Tab(
            url: URL(string: "https://example.com/page"),
            title: "Page",
            lastActive: Date(timeIntervalSince1970: 5_000))
        tab.faviconData = Data([1, 2])
        tab.snapshot = Data(repeating: 7, count: 16)
        try await persistence.saveIndex(TabIndex(openTabs: [tab], currentTabID: tab.id, archivedTabs: []))

        let loaded = try await persistence.loadIndex()
        #expect(loaded != nil)
        #expect(loaded?.openTabs.first?.snapshot == nil)
        #expect(loaded?.openTabs.first?.faviconData == Data([1, 2]))
        #expect(loaded?.openTabs.first?.title == "Page")
        #expect(loaded?.openTabs.first?.lastActive == Date(timeIntervalSince1970: 5_000))
        #expect(loaded?.currentTabID == tab.id)

        try await persistence.saveSnapshot(Data([3, 4]), for: tab.id)
        #expect(await persistence.loadSnapshot(for: tab.id) == Data([3, 4]))

        try await persistence.deleteSnapshot(for: tab.id)
        #expect(await persistence.loadSnapshot(for: tab.id) == nil)
    }

    @Test("a fresh store has no index")
    func freshStoreHasNoIndex() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileSystemTabPersistence(directory: directory)

        let index = try await persistence.loadIndex()
        #expect(index == nil)
    }
}
