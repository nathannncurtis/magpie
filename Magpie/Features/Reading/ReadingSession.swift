import Foundation
import Network
import Observation
import SwiftUI
import UIKit
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
    /// The site's own icon, when the page declares one.
    private(set) var pageIconURL: URL?
    /// Whether the network path is up.
    private(set) var isOnline = true

    let page = WebPage()

    /// Called whenever the page settles or moves, so the tab can take what it now shows.
    var onPageSettled: (@MainActor () -> Void)?

    /// The viewport the page is shown at, kept by the reading screen for captures.
    var viewportSize: CGSize?

    /// Whether the page has settled at least once — through the load event, or one of the
    /// screen's capture opportunities. The reuse refire waits for it, so a load still in
    /// flight never writes its half-state onto the tab.
    private(set) var hasSettled = false

    /// The page settles — the tab takes what it shows, capture included — whenever one of
    /// the screen's capture opportunities finds the page showing at a known viewport: the
    /// viewport arriving, the screen's session changing, or the page's URL committing.
    /// The load event's own settle is not relied on for the picture; it has not been seen
    /// to arrive on the simulator. This counts as a settle.
    func captureOpportunity() {
        guard viewportSize != nil, failure == nil, page.url != nil else { return }
        settleWithLateBeat()
    }

    /// The web view SwiftUI built for this page, kept by the reading screen's probe.
    /// Weak, because the hierarchy owns the view.
    @ObservationIgnored var webView: WKWebView?
    /// The probe's own walk to that view, retried at capture time — the view can be
    /// built after the probe first looks, and swapped for a new one later.
    @ObservationIgnored var webViewLookup: (@MainActor () -> WKWebView?)?

    private let initialURL: URL
    /// The URL the session last asked to load. Its host is what a failure names, so a
    /// failure always has one even when the page never got far enough to have a URL.
    private(set) var requestedURL: URL?
    private var loadTask: Task<Void, Never>?
    /// The site the icon link was last read for.
    private var iconHost: String?

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

    /// The site's icon link, for the tab's card and labels. Falls back to the touch icon
    /// a page declares for elsewhere; "" when the page declares none.
    private static let pageIconScript = #"""
        (() => {
            const icon = document.querySelector("link[rel~='icon']")
                || document.querySelector("link[rel='apple-touch-icon']");
            return icon ? icon.href : "";
        })()
        """#

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
                        await readPageIcon()
                        settle()
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

    /// Tells the owner the page settled. A title and the first paint can land after the
    /// moment that fired this, so it settles once more a beat later.
    private func settle() {
        settleWithLateBeat()
    }

    private func settleWithLateBeat() {
        hasSettled = true
        onPageSettled?()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.onPageSettled?()
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

    /// Reads the site's icon link from the page once per site, so the tab's card and
    /// labels can show it.
    private func readPageIcon() async {
        guard let host = page.url?.host(), host != iconHost else { return }
        iconHost = host
        guard
            let result = try? await page.callJavaScript(
                Self.pageIconScript, contentWorld: .defaultClient),
            let href = result as? String,
            let url = URL(string: href), url.scheme != nil
        else { return }
        pageIconURL = url
    }

    /// The page as an image: what the tab's card shows while the page itself is away. The
    /// page's own export is preferred; a renderer that never answers falls back to the
    /// web view, through the handle the reading screen's probe keeps. Both are capped: a
    /// page that misses both windows reads as nil, and a late answer is dropped. Every
    /// step is logged, because the captures are being diagnosed on the simulator.
    func snapshot(trigger: String) async -> Data? {
        let start = ContinuousClock.now
        guard failure == nil, page.url != nil else {
            SnapshotLog.event(
                "\(trigger) skip failure=\(failure != nil) url=\(page.url?.absoluteString ?? "nil")")
            return nil
        }
        guard let size = viewportSize else {
            SnapshotLog.event("\(trigger) skip viewport=nil")
            return nil
        }
        let region = WebPage.ExportedContentConfiguration.Region.rect(
            CGRect(origin: .zero, size: size))
        let exportThrown = ErrorBox()
        if let data = await capped(
            Self.exportCap,
            {
                do {
                    return try await self.page.exported(
                        as: .image(region: region, allowTransparentBackground: false))
                } catch {
                    exportThrown.error = error
                    return nil
                }
            })
        {
            SnapshotLog.event("\(trigger) export \(data.count)B \(Self.ms(since: start))ms")
            return data
        }
        if let error = exportThrown.error {
            SnapshotLog.event(
                "\(trigger) export nil \(Self.ms(since: start))ms error=\(Self.describe(error))")
        } else {
            SnapshotLog.event("\(trigger) export nil \(Self.ms(since: start))ms")
        }
        guard let found = onScreenWebView() else {
            SnapshotLog.event(
                "\(trigger) view none handle=\(webView != nil) probe=\(webViewLookup != nil)")
            return nil
        }
        let viewStart = ContinuousClock.now
        let viewThrown = ErrorBox()
        let data = await capped(
            Self.viewCap,
            {
                do {
                    return try await Self.viewSnapshot(found.view, Self.snapshotConfig(size))
                        .pngData()
                } catch {
                    viewThrown.error = error
                    return nil
                }
            })
        let outcome: String
        if let data {
            outcome = "\(data.count)B"
        } else if let error = viewThrown.error {
            outcome = "nil error=\(Self.describe(error))"
        } else {
            outcome = "nil"
        }
        SnapshotLog.event(
            "\(trigger) view[\(found.source)] \(outcome) \(Self.ms(since: viewStart))ms")
        return data
    }

    /// The web view's own snapshot, through its completion-based API.
    private static func viewSnapshot(
        _ view: WKWebView, _ config: WKSnapshotConfiguration
    ) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            view.takeSnapshot(with: config) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: SnapshotUnavailable())
                }
            }
        }
    }

    private static func snapshotConfig(_ size: CGSize) -> WKSnapshotConfiguration {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        return config
    }

    /// The web view SwiftUI built for this page: the probe's handle when it still holds,
    /// the probe's own walk otherwise. The page carries no view of its own.
    private func onScreenWebView() -> (view: WKWebView, source: String)? {
        if let view = webView, view.window != nil {
            return (view, "handle")
        }
        guard let view = webViewLookup?(), view.window != nil else { return nil }
        webView = view
        return (view, "probe")
    }

    /// An error, trimmed to sit on one log line.
    private static func describe(_ error: Error) -> String {
        let text = String(describing: error)
        return text.count <= 160 ? text : String(text.prefix(160)) + "…"
    }

    /// Milliseconds since the instant, for the log line.
    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let parts = (ContinuousClock.now - start).components
        return Int(parts.seconds) * 1_000
            + Int(parts.attoseconds / 1_000_000_000_000_000)
    }

    /// How long each capture path may take before the next one is tried. The export gets
    /// the longer window — it is the picture worth keeping — and the view path remains
    /// only its fallback.
    private static let exportCap: Duration = .milliseconds(1_000)
    private static let viewCap: Duration = .milliseconds(400)
}

extension ReadingSession: Equatable {

    /// Identity: the screen's change triggers compare sessions by who they are.
    nonisolated static func == (lhs: ReadingSession, rhs: ReadingSession) -> Bool {
        lhs === rhs
    }
}

extension UIView {

    /// The first subview of the given kind, depth first.
    func firstSubview<T: UIView>(of kind: T.Type) -> T? {
        if let found = self as? T { return found }
        for subview in subviews {
            if let found = subview.firstSubview(of: kind) { return found }
        }
        return nil
    }
}

/// Carries the error a capped-out capture threw, out to the log line.
@MainActor
private final class ErrorBox {
    var error: Error?
}

/// The web view answered with neither an image nor an error.
private struct SnapshotUnavailable: Error {}

/// Runs a capture under a cap: one that does not answer in time reads as nil. All on the
/// main actor, where the page lives.
@MainActor
private func capped(
    _ cap: Duration, _ capture: @escaping @MainActor () async -> Data?
) async -> Data? {
    await withCheckedContinuation { continuation in
        let gate = ResumeGate(continuation)
        Task { gate.resume(await capture()) }
        Task {
            try? await Task.sleep(for: cap)
            gate.resume(nil)
        }
    }
}

/// Hands the value to the first of many finishers; the rest are dropped.
@MainActor
private final class ResumeGate {
    private var continuation: CheckedContinuation<Data?, Never>?
    private var resumed = false

    init(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Data?) {
        guard !resumed else { return }
        resumed = true
        continuation?.resume(returning: value)
        continuation = nil
    }
}
