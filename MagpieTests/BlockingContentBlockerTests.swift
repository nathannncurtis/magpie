import Foundation
import Testing

@testable import Magpie

@Suite("ContentBlocker")
@MainActor
struct BlockingContentBlockerTests {

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "blocking-tests-\(UUID().uuidString)")
        return defaults ?? .standard
    }

    private func makeBlocker(defaults: UserDefaults) -> ContentBlocker {
        let directory = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)
        return ContentBlocker(store: FilterListStore(directory: directory), defaults: defaults)
    }

    @Test("both toggles default on")
    func togglesDefaultOn() {
        let blocker = makeBlocker(defaults: makeDefaults())
        #expect(blocker.blocksAdsAndTrackers)
        #expect(blocker.blocksCookieBanners)
    }

    @Test("toggles persist and a fresh blocker reads them back")
    func togglesPersist() {
        let defaults = makeDefaults()
        let blocker = makeBlocker(defaults: defaults)
        blocker.blocksAdsAndTrackers = false
        blocker.blocksCookieBanners = false

        #expect(!defaults.bool(forKey: "blocksAdsAndTrackers"))
        #expect(!defaults.bool(forKey: "blocksCookieBanners"))

        let reread = makeBlocker(defaults: defaults)
        #expect(!reread.blocksAdsAndTrackers)
        #expect(!reread.blocksCookieBanners)
    }

    @Test("the updated text reads like the Settings row")
    func updatedText() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let english = Locale(identifier: "en_US")
        #expect(ContentBlocker.updatedText(from: nil, now: now) == "Not updated yet")
        #expect(
            ContentBlocker.updatedText(from: now.addingTimeInterval(-45), now: now, locale: english)
                == "Updated just now"
        )
        #expect(
            ContentBlocker.updatedText(from: now.addingTimeInterval(-120 * 60), now: now, locale: english)
                == "Updated 2h ago"
        )
        #expect(
            ContentBlocker.updatedText(from: now.addingTimeInterval(-25 * 3600), now: now, locale: english)
                == "Updated 1d ago"
        )
        #expect(
            ContentBlocker.updatedText(from: now.addingTimeInterval(60), now: now, locale: english)
                == "Updated just now"
        )
    }

    @Test("refresh pulls the store's overall timestamp")
    func refreshUpdatesTimestamp() async throws {
        let downloaded = Date(timeIntervalSince1970: 1_700_000_000)
        let directory = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = FilterListStore.PersistedState(
            lists: [
                "easylist": FilterListStore.ListRecord(
                    etag: nil,
                    lastModified: nil,
                    lastUpdated: downloaded
                )
            ]
        )
        try JSONEncoder().encode(state).write(to: directory.appending(component: "state.json"))

        // No lists, so the refresh can't touch the network.
        let store = FilterListStore(lists: [], directory: directory)
        let blocker = ContentBlocker(store: store, defaults: makeDefaults())
        #expect(blocker.lastUpdated == nil)
        await blocker.refresh()
        #expect(blocker.lastUpdated == downloaded)
    }
}
