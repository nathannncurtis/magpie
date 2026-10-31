import Foundation
import Testing

@testable import Magpie

@Suite("Persisted files")
struct PersistedFileTests {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("persisted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a truncated tab index loads as nil and is kept aside as .corrupt")
    func corruptTabIndex() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let home = directory.appendingPathComponent("Magpie/TabStore", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let index = home.appendingPathComponent("index.json")
        let garbage = Data(#"{"openTabs":[{"id":"#.utf8)
        try garbage.write(to: index)

        let persistence = FileSystemTabPersistence(directory: directory)
        let loaded = try await persistence.loadIndex()
        #expect(loaded == nil)
        #expect(!FileManager.default.fileExists(atPath: index.path))
        let backup = try Data(contentsOf: index.appendingPathExtension("corrupt"))
        #expect(backup == garbage)
    }

    @Test("a corrupt bookmark index opens an empty store and keeps the old file")
    @MainActor
    func corruptBookmarkIndex() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let home = directory.appendingPathComponent("Magpie/BookmarkStore", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let index = home.appendingPathComponent("bookmarks.json")
        try Data("not json".utf8).write(to: index)

        let store = BookmarkStore(persistence: FileSystemBookmarkPersistence(directory: directory))
        await store.loadIndex()
        #expect(store.bookmarks.isEmpty)
        #expect(FileManager.default.fileExists(atPath: index.appendingPathExtension("corrupt").path))
    }

    @Test("a tab index written before optional fields existed still decodes")
    func oldTabIndex() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let home = directory.appendingPathComponent("Magpie/TabStore", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
            {"openTabs":[{"id":"\(id.uuidString)","title":"A","lastActive":"2026-01-01T00:00:00Z"}],
             "archivedTabs":[]}
            """
        try Data(json.utf8).write(to: home.appendingPathComponent("index.json"))

        let loaded = try await FileSystemTabPersistence(directory: directory).loadIndex()
        #expect(loaded?.openTabs.map(\.id) == [id])
        #expect(loaded?.openTabs.first?.url == nil)
        #expect(loaded?.openTabs.first?.faviconURL == nil)
        #expect(loaded?.currentTabID == nil)
    }

    @Test("a bookmark index without favicons or folders on its bookmarks still decodes")
    func oldBookmarkIndex() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let home = directory.appendingPathComponent("Magpie/BookmarkStore", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let json = """
            {"bookmarks":[{"id":"\(UUID().uuidString)","url":"https://a.example","title":"A",
              "addedAt":"2026-01-01T00:00:00Z","kind":"page"}],"folders":[]}
            """
        try Data(json.utf8).write(to: home.appendingPathComponent("bookmarks.json"))

        let loaded = try await FileSystemBookmarkPersistence(directory: directory).loadIndex()
        #expect(loaded?.bookmarks.first?.title == "A")
        #expect(loaded?.bookmarks.first?.faviconData == nil)
        #expect(loaded?.bookmarks.first?.folderID == nil)
    }

    @Test("a corrupt mods index loads empty and is kept aside; the mod values survive")
    func corruptModsIndex() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let io = FileSystemModStoreIO(directory: directory)
        io.save(values: ["k": "v"], modID: "m")
        try Data("[{".utf8).write(to: directory.appending(component: "mods.json"))

        #expect(io.loadMods().isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: directory.appending(component: "mods.json.corrupt").path))
        #expect(io.loadValues(modID: "m") == ["k": "v"])
    }
}
