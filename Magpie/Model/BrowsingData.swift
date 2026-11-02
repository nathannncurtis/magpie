import Foundation
import WebKit

/// What the Clear browsing data page can clear.
struct BrowsingDataKinds: Equatable, Sendable {
    var history = true
    var cookiesAndSiteData = true
    var cache = true

    /// Whether nothing is ticked.
    var isEmpty: Bool { !history && !cookiesAndSiteData && !cache }

    /// The website data types the ticks stand for. Cookies and site data are everything
    /// the store keeps that is not a cache.
    @MainActor var websiteDataTypes: Set<String> {
        var types: Set<String> = []
        if cookiesAndSiteData {
            types.formUnion(WKWebsiteDataStore.allWebsiteDataTypes().subtracting(Self.cacheTypes))
        }
        if cache {
            types.formUnion(Self.cacheTypes)
        }
        return types
    }

    private static let cacheTypes: Set<String> = [
        WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache,
    ]
}
