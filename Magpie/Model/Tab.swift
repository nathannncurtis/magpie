import Foundation

/// One tab: open, or resting in the archive.
///
/// `snapshot` is image data held in memory only; the JSON index never carries it, and each
/// snapshot is written as its own file keyed by the tab id.
struct Tab: Identifiable, Codable, Equatable, Sendable {
    typealias ID = UUID

    /// A stable identity across the stack, the archive and persistence.
    let id: ID
    /// The page the tab shows; nil until the tab's first page loads.
    var url: URL?
    /// The page title as Magpie shows it.
    var title: String
    /// Where the site's favicon lives, once a pipeline supplies it.
    var faviconURL: URL?
    /// Cached favicon image data.
    var faviconData: Data?
    /// When the tab was last the reading tab.
    var lastActive: Date
    /// Set when the tab moves to the archive.
    var archivedAt: Date?
    /// The page snapshot shown on the tab card. Never part of the index.
    var snapshot: Data? = nil
    /// A private tab: never written to disk, never archived, and its pages keep their
    /// cookies and storage in memory only. Not coded, so it can never be saved.
    var isPrivate = false

    init(
        id: ID = ID(),
        url: URL? = nil,
        title: String = "",
        faviconURL: URL? = nil,
        faviconData: Data? = nil,
        lastActive: Date,
        archivedAt: Date? = nil,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconURL = faviconURL
        self.faviconData = faviconData
        self.lastActive = lastActive
        self.archivedAt = archivedAt
        self.isPrivate = isPrivate
    }

    /// The host without its www prefix, for labels and favicon fallbacks.
    var host: String? {
        guard let host = url?.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The title the tab card shows: the page title, else the host.
    var displayTitle: String {
        title.isEmpty ? (host ?? "") : title
    }

    enum CodingKeys: String, CodingKey {
        case id, url, title, faviconURL, faviconData, lastActive, archivedAt
    }
}
