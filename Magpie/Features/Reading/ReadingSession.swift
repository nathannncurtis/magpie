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
        host.isEmpty
            ? String(localized: "Can't reach this page")
            : String(localized: "Can't reach \(host)")
    }

    var line: String {
        if isOffline {
            return String(localized: "You're offline. It'll load when you're back.")
        }
        // COPY: review — 06 still has this line to write.
        return String(localized: "It didn't answer. Try again in a moment.")
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
    /// The URL the session last asked to load. Its host is what a failure names, so a
    /// failure always has one even when the page never got far enough to have a URL.
    private(set) var requestedURL: URL?
    private var loadTask: Task<Void, Never>?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.magpiebrowser.reading.path")

    /// Reads the page's effective background colour in the appearance it is currently
    /// rendered under, as "r,g,b"; "" when none can be read. The nearest opaque
    /// background on body and its ancestors wins, otherwise the page's canvas colour —
    /// which follows the page's colour scheme, so the value flips with the appearance.
    private static let pageBackgroundScript = #"""
        const rgb = (s) => {
            const m = s && s.match(/^rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)$/);
            return (!m || m[4] === undefined || parseFloat(m[4]) !== 0) ? m : null;
        };
        let el = document.body;
        while (el) {
            const m = rgb(getComputedStyle(el).backgroundColor);
            if (m) { return m[1] + "," + m[2] + "," + m[3]; }
            el = el.parentElement;
        }
        const probe = document.createElement("div");
        probe.style.cssText = "position:fixed;left:-9999px;top:0;background-color:Canvas";
        (document.body || document.documentElement).appendChild(probe);
        const m = rgb(getComputedStyle(probe).backgroundColor);
        probe.remove();
        return m ? m[1] + "," + m[2] + "," + m[3] : "";
        """#

    init(url: URL) {
        initialURL = url
        requestedURL = url
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
        requestedURL = url
        startLoad { self.page.load(url) }
    }

    /// Reloads the current page: "Try again", or the connection coming back.
    func retry() {
        startLoad { self.page.reload() }
    }

    /// Goes back one page.
    func goBack() {
        guard let back = page.backForwardList.backList.last else { return }
        requestedURL = back.url
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
        failure = PageLoadFailure(
            host: HostFormatter.host(for: requestedURL ?? page.url), isOffline: offline)
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
    /// theme colour of its own. Re-run whenever the appearance changes — a page that
    /// follows the colour scheme renders a different background under each.
    func refreshPageBackground() async {
        guard page.themeColor == nil, page.url != nil else { return }
        guard
            let result = try? await page.callJavaScript(
                Self.pageBackgroundScript, contentWorld: .defaultClient),
            let text = result as? String
        else { return }
        pageBackground = PageBackgroundColor.parse(text)
    }
}
