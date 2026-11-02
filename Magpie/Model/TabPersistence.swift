import Foundation

/// The saved state of the tab store.
struct TabIndex: Codable, Equatable, Sendable {
    /// The open tabs, in stack order.
    var openTabs: [Tab]
    /// The tab the stack centers on.
    var currentTabID: Tab.ID?
    /// The archived tabs, oldest first.
    var archivedTabs: [Tab]
}

/// Where the tab store keeps its index and its snapshots. Snapshots are always separate
/// files keyed by tab id, never rows of image data inside the index. Tests use the
/// in-memory implementation; the app uses the file-system one.
protocol TabPersistence: Sendable {
    /// The stored index, or nil when nothing has been written yet.
    func loadIndex() async throws -> TabIndex?
    /// Replaces the stored index.
    func saveIndex(_ index: TabIndex) async throws
    /// The tab's snapshot file, or nil when there is none.
    func loadSnapshot(for id: Tab.ID) async -> Data?
    /// Writes the tab's snapshot file.
    func saveSnapshot(_ data: Data, for id: Tab.ID) async throws
    /// Removes the tab's snapshot file.
    func deleteSnapshot(for id: Tab.ID) async throws
}

/// A JSON index in Application Support, one image file per snapshot.
actor FileSystemTabPersistence: TabPersistence {
    private let indexURL: URL
    private let snapshotsDirectory: URL

    /// `directory` overrides the store's home; tests point it at a scratch folder.
    init(directory: URL? = nil) {
        let support =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let home = (directory ?? support)
            .appendingPathComponent("Magpie/TabStore", isDirectory: true)
        indexURL = home.appendingPathComponent("index.json")
        snapshotsDirectory = home.appendingPathComponent("snapshots", isDirectory: true)
    }

    func loadIndex() async throws -> TabIndex? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return PersistedFile.decode(TabIndex.self, from: indexURL, decoder: decoder)
    }

    func saveIndex(_ index: TabIndex) async throws {
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

    func loadSnapshot(for id: Tab.ID) async -> Data? {
        let url = snapshotURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func saveSnapshot(_ data: Data, for id: Tab.ID) async throws {
        try FileManager.default.createDirectory(
            at: snapshotsDirectory, withIntermediateDirectories: true)
        // Snapshots are redrawn from the page; they stay out of backups.
        PersistedFile.excludeFromBackup(snapshotsDirectory)
        try data.write(to: snapshotURL(for: id), options: .atomic)
    }

    func deleteSnapshot(for id: Tab.ID) async throws {
        let url = snapshotURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func snapshotURL(for id: Tab.ID) -> URL {
        snapshotsDirectory.appendingPathComponent("\(id.uuidString).png")
    }
}

/// Keeps the index and snapshots in memory; nothing touches the disk.
actor InMemoryTabPersistence: TabPersistence {
    private var index: TabIndex?
    private var snapshots: [Tab.ID: Data] = [:]

    init(index: TabIndex? = nil) {
        self.index = index
    }

    func loadIndex() async throws -> TabIndex? { index }

    func saveIndex(_ index: TabIndex) async throws { self.index = index }

    func loadSnapshot(for id: Tab.ID) async -> Data? { snapshots[id] }

    func saveSnapshot(_ data: Data, for id: Tab.ID) async throws { snapshots[id] = data }

    func deleteSnapshot(for id: Tab.ID) async throws { snapshots[id] = nil }
}
