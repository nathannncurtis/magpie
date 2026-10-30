import Foundation

/// Recent search queries, most recent first. Persistence lands later; the protocol is the seam.
protocol RecentSearchStoring: Sendable {
    /// The most recent queries, freshest first, at most `limit`.
    func recent(limit: Int) async -> [String]
    /// Records a query, moving it to the front if it was already there.
    func record(_ query: String) async
    /// Forgets everything.
    func removeAll() async
}

/// In-memory recent searches.
actor RecentSearches: RecentSearchStoring {

    /// How many queries are kept at all; the sheet shows far fewer.
    private let capacity: Int
    private var queries: [String] = []

    /// Starts empty, or with `seed` already recorded, oldest first.
    init(capacity: Int = 20, seed: [String] = []) {
        self.capacity = capacity
        self.queries = Array(seed.suffix(capacity).reversed())
    }

    func recent(limit: Int) async -> [String] {
        Array(queries.prefix(limit))
    }

    func record(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queries.removeAll { $0 == trimmed }
        queries.insert(trimmed, at: 0)
        if queries.count > capacity {
            queries.removeLast(queries.count - capacity)
        }
    }

    func removeAll() async {
        queries = []
    }
}
