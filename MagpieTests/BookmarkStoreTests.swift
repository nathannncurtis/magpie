import Foundation
import Testing

@testable import Magpie

@Suite("BookmarkStore")
@MainActor
struct BookmarkStoreTests {

    /// Dates from a zero base, so ordering comparisons stay exact.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func url(_ address: String) -> URL {
        URL(string: address) ?? URL(fileURLWithPath: "/")
    }

    @Test("a saved page is held and stamped with its date")
    func addHoldsBookmark() {
        let store = BookmarkStore()
        let saved = store.add(
            url: url("https://quietweb.org/slow"), title: "The web, read slowly",
            now: date(10))

        #expect(store.bookmarks == [saved])
        #expect(saved.addedAt == date(10))
        #expect(saved.kind == .page)
        #expect(saved.folderID == nil)
        #expect(saved.host == "quietweb.org")
    }

    @Test("a Skim page carries the hosts it was read from")
    func skimPageCarriesSources() {
        let store = BookmarkStore()
        let saved = store.add(
            url: url("https://magpie.test/skim/seasoning"), title: "Seasoning carbon steel",
            kind: .skim(sourceHosts: ["seriouseats.com", "debuyer.com"]), now: date(0))

        #expect(saved.kind == .skim(sourceHosts: ["seriouseats.com", "debuyer.com"]))
    }

    @Test("removing a bookmark leaves the rest")
    func removeKeepsTheRest() {
        let store = BookmarkStore()
        let kept = store.add(url: url("https://a.example"), title: "A", now: date(0))
        let gone = store.add(url: url("https://b.example"), title: "B", now: date(1))

        store.remove(gone.id)

        #expect(store.bookmarks.map(\.id) == [kept.id])
    }

    @Test("recently added runs newest first")
    func recentlyAddedNewestFirst() {
        let store = BookmarkStore()
        store.add(url: url("https://old.example"), title: "Old", now: date(0))
        store.add(url: url("https://new.example"), title: "New", now: date(100))
        store.add(url: url("https://middle.example"), title: "Middle", now: date(50))

        #expect(store.recentlyAdded.map(\.title) == ["New", "Middle", "Old"])
    }

    // MARK: Folders

    @Test("folders keep their list order and count their bookmarks")
    func foldersOrderAndCount() {
        let store = BookmarkStore()
        let kitchen = store.newFolder(name: "Kitchen", tint: .orange)
        let work = store.newFolder(name: "Work", tint: .sage)
        store.add(url: url("https://a.example"), title: "A", folder: kitchen.id, now: date(0))
        store.add(url: url("https://b.example"), title: "B", folder: kitchen.id, now: date(1))
        store.add(url: url("https://c.example"), title: "C", folder: work.id, now: date(2))

        #expect(store.folders.map(\.name) == ["Kitchen", "Work"])
        #expect(store.count(inFolder: kitchen.id) == 2)
        #expect(store.count(inFolder: work.id) == 1)
        #expect(store.bookmarks(inFolder: kitchen.id).map(\.title) == ["B", "A"])
    }

    @Test("new folders take the next preset tint")
    func defaultFoldersCycleTints() {
        let store = BookmarkStore()
        for index in FolderTint.allCases.indices {
            let folder = store.newFolder(name: "Folder \(index)")
            #expect(folder.tint == FolderTint.allCases[index])
        }
        let seventh = store.newFolder(name: "Seventh")
        #expect(seventh.tint == FolderTint.allCases[0])
    }

    @Test("a default folder is numbered past the ones that exist")
    func defaultFolderNumbering() {
        let store = BookmarkStore()
        store.newFolder(name: "Something else", tint: .blue)

        let first = store.addDefaultFolder()
        #expect(first.name == "New folder")
        let second = store.addDefaultFolder()
        #expect(second.name == "New folder 2")
    }

    @Test("a folder is renamed in place")
    func renameKeepsPlace() {
        let store = BookmarkStore()
        let kitchen = store.newFolder(name: "Kitchen", tint: .orange)
        store.newFolder(name: "Work", tint: .sage)

        store.renameFolder(kitchen.id, to: "Cooking")

        #expect(store.folders.map(\.name) == ["Cooking", "Work"])
    }

    @Test("moving a folder rewrites the order")
    func moveRewritesOrder() {
        let store = BookmarkStore()
        _ = store.newFolder(name: "A", tint: .orange)
        let b = store.newFolder(name: "B", tint: .blue)
        let c = store.newFolder(name: "C", tint: .sage)

        store.moveFolders(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(store.folders.map(\.name) == ["C", "A", "B"])
        #expect(store.folders.map(\.order) == [0, 1, 2])
        #expect(store.folders.first?.id == c.id)
        #expect(store.folders.last?.id == b.id)
    }

    @Test("deleting a folder keeps its bookmarks, unfiled")
    func deleteFolderUnfilesBookmarks() {
        let store = BookmarkStore()
        let kitchen = store.newFolder(name: "Kitchen", tint: .orange)
        store.add(url: url("https://a.example"), title: "A", folder: kitchen.id, now: date(0))

        store.removeFolder(kitchen.id)

        #expect(store.folders.isEmpty)
        #expect(store.bookmarks.count == 1)
        #expect(store.bookmarks.first?.folderID == nil)
        #expect(store.recentlyAdded.map(\.title) == ["A"])
    }

    // MARK: Persistence

    @Test("the index round-trips through the file store")
    func filePersistenceRoundTrip() async throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bookmark-store-tests", isDirectory: true)
        try? FileManager.default.removeItem(at: scratch)
        let persistence = FileSystemBookmarkPersistence(directory: scratch)

        let writer = BookmarkStore(persistence: persistence)
        let kitchen = writer.newFolder(name: "Kitchen", tint: .orange)
        writer.add(
            url: url("https://quietweb.org/slow"), title: "The web, read slowly",
            folder: kitchen.id, now: date(1_000))
        writer.add(
            url: url("https://magpie.test/skim/seasoning"), title: "Seasoning carbon steel",
            kind: .skim(sourceHosts: ["seriouseats.com", "debuyer.com"]), now: date(2_000))
        await writer.flushWrites()

        let reader = BookmarkStore(persistence: persistence)
        await reader.loadIndex()

        #expect(reader.folders == [kitchen])
        #expect(reader.bookmarks == writer.bookmarks)
        #expect(reader.recentlyAdded.map(\.title) == ["Seasoning carbon steel", "The web, read slowly"])
        try? FileManager.default.removeItem(at: scratch)
    }

    @Test("the index round-trips through memory")
    func inMemoryRoundTrip() async {
        let persistence = InMemoryBookmarkPersistence()
        let writer = BookmarkStore(persistence: persistence)
        let folder = writer.newFolder(name: "Reading", tint: .blue)
        writer.add(url: url("https://a.example"), title: "A", folder: folder.id, now: date(0))
        await writer.flushWrites()

        let reader = BookmarkStore(persistence: persistence)
        await reader.loadIndex()

        #expect(reader.folders.map(\.name) == ["Reading"])
        #expect(reader.bookmarks.map(\.title) == ["A"])
    }

    @Test("a store with nothing behind it stays empty on load")
    func loadWithoutPersistence() async {
        let store = BookmarkStore()
        store.add(url: url("https://a.example"), title: "A", now: date(0))

        await store.loadIndex()

        #expect(store.bookmarks.count == 1)
    }

    @Test("a folder's bookmarks run newest first, and only its own")
    func folderContentsNewestFirst() {
        let store = BookmarkStore()
        let folder = store.newFolder(name: "Reading")
        let older = store.add(url: url("https://a.example"), title: "A", folder: folder.id, now: date(0))
        store.add(url: url("https://b.example"), title: "B", now: date(5))
        let newer = store.add(url: url("https://c.example"), title: "C", folder: folder.id, now: date(10))

        #expect(store.bookmarks(inFolder: folder.id).map(\.id) == [newer.id, older.id])
        #expect(store.count(inFolder: folder.id) == 2)
    }

    @Test("a folder made after a move goes to the end of the list")
    func newFolderAfterMove() {
        let store = BookmarkStore()
        let first = store.newFolder(name: "One")
        let second = store.newFolder(name: "Two")
        store.moveFolders(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let third = store.newFolder(name: "Three")

        #expect(store.folders.map(\.id) == [second.id, first.id, third.id])
        #expect(third.order > store.folders.map(\.order).filter { $0 != third.order }.max()!)
    }

    @Test("a favicon lands on its bookmark and in the saved index")
    func faviconPersists() async throws {
        let persistence = InMemoryBookmarkPersistence()
        let store = BookmarkStore(persistence: persistence)
        let saved = store.add(url: url("https://a.example"), title: "A", now: date(0))

        store.setFavicon(Data([1, 2, 3]), for: saved.id)
        await store.flushWrites()

        #expect(store.bookmarks.first?.faviconData == Data([1, 2, 3]))
        let reloaded = BookmarkStore(persistence: persistence)
        await reloaded.loadIndex()
        #expect(reloaded.bookmarks.first?.faviconData == Data([1, 2, 3]))
    }

    @Test("renames and unknown ids leave the other folders alone")
    func unknownFolderIsANoOp() {
        let store = BookmarkStore()
        let folder = store.newFolder(name: "Kept")

        store.renameFolder(UUID(), to: "Nope")
        store.removeFolder(UUID())

        #expect(store.folders.map(\.name) == ["Kept"])
        #expect(store.folders.first?.id == folder.id)
    }

    @Test("a removed bookmark comes back on undo")
    func reinstateBookmark() {
        let store = BookmarkStore()
        let saved = store.add(url: url("https://quietweb.org/slow"), title: "Slow", now: date(1))

        let removed = store.remove(saved.id)
        #expect(store.bookmarks.isEmpty)

        if let removed { store.reinstate(removed) }
        #expect(store.bookmarks == [saved])
    }

    @Test("a deleted folder comes back in its place with the bookmarks it held")
    func reinstateFolder() {
        let store = BookmarkStore()
        let first = store.newFolder(name: "First")
        let second = store.newFolder(name: "Second")
        let third = store.newFolder(name: "Third")
        let inSecond = store.add(
            url: url("https://a.example/1"), title: "One", folder: second.id, now: date(1))
        let elsewhere = store.add(
            url: url("https://a.example/2"), title: "Two", folder: third.id, now: date(2))

        let removed = store.removeFolder(second.id)
        #expect(store.folders.map(\.name) == ["First", "Third"])
        #expect(store.bookmarks.first { $0.id == inSecond.id }?.folderID == nil)

        if let removed { store.reinstate(removed) }
        #expect(store.folders.map(\.id) == [first.id, second.id, third.id])
        #expect(store.folders.map(\.order) == [0, 1, 2])
        #expect(store.bookmarks.first { $0.id == inSecond.id }?.folderID == second.id)
        #expect(store.bookmarks.first { $0.id == elsewhere.id }?.folderID == third.id)
    }
}
