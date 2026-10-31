import Foundation
import UIKit

/// The bytes behind a site's favicon: fetched off the main actor, kept by address, so
/// every tab and bookmark pointing at one site shares a single download.
actor FaviconFetcher {

    /// A favicon past this size is not worth keeping; the tiles draw at 26 pt.
    private static let byteLimit = 128 * 1024
    /// How long an address that gave no usable icon stays unanswered. Every settle asks
    /// again, so without this a site with no icon to give is re-downloaded each time.
    private static let failureTTL: TimeInterval = 10 * 60

    /// The icons already fetched, by the address they came from.
    private var cached: [URL: Data] = [:]
    /// The downloads in flight, so rows asking together make one request.
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    /// The addresses that answered with no usable icon, and when they did.
    private var failedAt: [URL: Date] = [:]

    /// The icon's bytes, from the cache when they are there and otherwise from the wire.
    /// A nil is no icon: the miss is remembered for a short while, then tried again.
    func favicon(at url: URL) async -> Data? {
        if let data = cached[url] { return data }
        if let failed = failedAt[url], Date.now.timeIntervalSince(failed) < Self.failureTTL {
            return nil
        }
        if let running = inFlight[url] { return await running.value }
        let download = Task { await Self.download(url) }
        inFlight[url] = download
        let data = await download.value
        inFlight[url] = nil
        if let data {
            cached[url] = data
            failedAt[url] = nil
        } else {
            failedAt[url] = .now
        }
        return data
    }

    /// The site's own bytes, when they arrive whole, small enough, and decodable as an
    /// image. Anything else leaves the letter tile in place.
    private static func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        guard
            (response as? HTTPURLResponse)?.statusCode == 200,
            data.count <= byteLimit,
            UIImage(data: data) != nil
        else { return nil }
        return data
    }
}
