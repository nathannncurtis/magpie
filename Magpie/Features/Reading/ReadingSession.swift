import Foundation
import Network
import Observation
import SwiftUI
import WebKit

/// What the can't-load page says (04 · 15; copy in 06 · Edge states).
struct PageLoadFailure {
    /// The host the page was on, in display form.
    let host: String
    /// Whether the network path was down.
    let isOffline: Bool

    var title: String {
        host.isEmpty ? "Can't reach this page" : "Can't reach \(host)"
    }

    var line: String {
        if isOffline {
            return "You're offline. It'll load when you're back."
        }
        // COPY: review — the non-offline line is a draft; 06 still has it to write.
        return "The page didn't load. Try again in a moment."
    }
}

/// The page's own background colour, read back from the page as "r,g,b" and used as the
/// bar tint when the page declares no theme colour.
enum PageBackgroundColor {

    static func parse(_ text: String) -> Color? {
        let parts = text.split(separator: ",").compactMap { part in
            let channel = Double(part.trimmingCharacters(in: .whitespaces))
            return (channel.map { (0.0...255.0).contains($0) } ?? false) ? channel : nil
        }
        guard parts.count == 3 else { return nil }
        return Color(
            red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
    }
}

/// One page being read: the web page it shows, the bar tint, and the connection watch.
@MainActor @Observable
final class ReadingSession {

    /// The page's load failure; nil while a page shows.
    private(set) var failure: PageLoadFailure?
    /// The page's own background, when it sets one and declares no theme colour.
    private(set) var pageBackground: Color?
    /// Whether the network path is up.
    private(set) var isOnline = true

    let page = WebPage()

    private let initialURL: URL
    private var loadTask: Task<Void, Never>?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.magpiebrowser.reading.path")

    /// Reads the page's effective background colour as "r,g,b", or "" when it sets none.
    private static let pageBackgroundScript = #"""
        const found = (function() {
            let el = document.body;
            while (el) {
                const m = getComputedStyle(el).backgroundColor
                    .match(/^rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)$/);
                if (m && (m[4] === undefined || parseFloat(m[4]) !== 0)) {
                    return m[1] + "," + m[2] + "," + m[3];
                }
                el = el.parentElement;
            }
            return "";
        })();
        return found;
        """#

    init(url: URL) {
        initialURL = url
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.connectivityChanged(online)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    var canGoBack: Bool {
        !page.backForwardList.backList.isEmpty
    }

    /// Starts the session: the first load, then the standing watch on navigation events.
    func run() async {
        open(initialURL)
        while !Task.isCancelled {
            do {
                for try await event in page.navigations {
                    if event == .committed {
                        failure = nil
                    }
                    if event == .finished {
                        await refreshPageBackground()
                    }
                }
                return
            } catch is CancellationError {
                return
            } catch {
                // A single load's failure also lands here; the load's own sequence
                // records it, so keep listening for the rest of the session.
                if case WebPage.NavigationError.failedProvisionalNavigation = error { continue }
                return
            }
        }
    }

    /// Loads a page outright.
    func open(_ url: URL) {
        startLoad { self.page.load(url) }
    }

    /// Reloads the current page: "Try again", or the connection coming back.
    func retry() {
        startLoad { self.page.reload() }
    }

    /// Goes back one page.
    func goBack() {
        guard let back = page.backForwardList.backList.last else { return }
        startLoad { self.page.load(back) }
    }

    private func startLoad(
        _ events: () -> some AsyncSequence<WebPage.NavigationEvent, Error>
    ) {
        failure = nil
        pageBackground = nil
        loadTask?.cancel()
        let sequence = events()
        loadTask = Task { [weak self] in
            await self?.drive(sequence)
        }
    }

    /// Observes one load: a throw is the page failing to load.
    private func drive<Events: AsyncSequence>(_ events: Events) async
    where Events.Element == WebPage.NavigationEvent, Events.Failure == Error {
        do {
            for try await _ in events {}
        } catch {
            fail(with: error)
        }
    }

    private func fail(with error: Error) {
        guard !Task.isCancelled else { return }
        let underlying: Error
        if case WebPage.NavigationError.failedProvisionalNavigation(let inner) = error {
            underlying = inner
        } else {
            underlying = error
        }
        var offline = false
        if let urlError = underlying as? URLError {
            offline = [
                .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
            ].contains(urlError.code)
        }
        failure = PageLoadFailure(host: HostFormatter.host(for: page.url), isOffline: offline)
        pageBackground = nil
    }

    private func connectivityChanged(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online, wasOffline, failure?.isOffline == true {
            retry()
        }
    }

    /// The under-page background: what the bar tints with when the page declares no
    /// theme colour of its own.
    private func refreshPageBackground() async {
        guard page.themeColor == nil, page.url != nil else { return }
        guard
            let result = try? await page.callJavaScript(
                Self.pageBackgroundScript, contentWorld: .defaultClient),
            let text = result as? String
        else { return }
        pageBackground = PageBackgroundColor.parse(text)
    }
}
