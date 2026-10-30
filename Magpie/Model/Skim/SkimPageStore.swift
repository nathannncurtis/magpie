import Foundation

/// Saves finished Skim pages as JSON under Application Support, so a bookmark
/// can bring one back without reading its sources again.
struct SkimPageStore: Sendable {

    static let scheme = "magpie"

    /// The host of a saved page's address: `magpie://skim/<id>`.
    static let host = "skim"

    let directory: URL

    init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkimPages", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// The address a saved page is bookmarked under.
    static func address(forID id: UUID) -> URL? {
        URL(string: "\(scheme)://\(host)/\(id.uuidString)")
    }

    /// The page a bookmark address points at, when it is one.
    static func pageID(forBookmarkURL url: URL) -> UUID? {
        guard
            url.scheme == scheme,
            HostFormatter.host(for: url) == host,
            let id = UUID(uuidString: url.lastPathComponent)
        else { return nil }
        return id
    }

    @discardableResult
    func save(_ page: SkimPage, id: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(page) else { return false }
        do {
            try data.write(to: file(id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func load(id: UUID) -> SkimPage? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(SkimPage.self, from: data)
    }

    private func file(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }
}
