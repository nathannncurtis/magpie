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

/// What a capture came to: a picture, a miss, or a page that has not laid out yet — a
/// miss the retry ladder owns, a not-ready one it does not.
enum CaptureOutcome {
    case stored(Data)
    case miss
    case notReady
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

    /// The page this session reads. It carries the shared content configuration, so every
    /// page runs the mods' scripts under the same rules.
    let page: WebPage

    /// Called whenever the page settles or moves, so the tab can take what it now shows.
    var onPageSettled: (@MainActor () -> Void)?

    /// Called when the page's title lands, so the tab's label follows the page itself —
    /// the settle moments can stop before a title arrives.
    var onPageTitled: (@MainActor () -> Void)?

    /// The viewport the page is shown at, kept by the reading screen for captures.
    var viewportSize: CGSize?

    /// The tab this session serves, for the log: set by the owner when the session is
    /// made, so every line names the page it belongs to.
    @ObservationIgnored var logTag = "tab=----"

    /// The standing wait for the page's first layout, while a capture is held back.
    @ObservationIgnored private var layoutWatch: Task<Void, Never>?
    /// Whether the root is drawing this page unseen, in the window, for its picture. A
    /// page with no view anywhere is laid out wrong, and is never captured.
    @ObservationIgnored var isDrawnUnseen = false {
        didSet {
            // Back in the window with its load done: a held picture can be taken now.
            guard isDrawnUnseen, !oldValue, hasSettled, !page.isLoading else { return }
            settleWithLateBeat()
        }
    }
    /// The standing wait for the current load to be done, whatever the event streams say.
    @ObservationIgnored private var loadWatch: Task<Void, Never>?

    /// Whether the page has settled at least once — through the load event, or one of the
    /// screen's capture opportunities. The reuse refire waits for it, so a load still in
    /// flight never writes its half-state onto the tab.
    private(set) var hasSettled = false

    /// The page settles — the tab takes what it shows, capture included — whenever one of
    /// the screen's capture opportunities finds the page showing at a known viewport: the
    /// viewport arriving, the screen's session changing, or the page's URL committing.
    /// The load event's own settle is not relied on for the picture; it has not been seen
    /// to arrive on the simulator. This counts as a settle. A page that has not laid out
    /// yet settles later, when its content lands: a capture against no layout cannot
    /// show the page. The page's own colour is sampled only once a picture has been
    /// stored, never here: running page JavaScript at commit time sits before the first
    /// paint and has been seen to stall the load.
    func captureOpportunity() {
        // A page still loading shows the last page, or nothing: its picture waits for the
        // load to be done, which the load watch reports.
        guard viewportSize != nil, failure == nil, page.url != nil, !page.isLoading else {
            return
        }
        guard let found = onScreenWebView() else {
            // No view at all: the page is off screen, and nothing can land there. Its
            // settle comes from the load's own end, watched apart from the screen.
            return
        }
        guard found.view.scrollView.contentSize.width > 0 else {
            watchForLayout()
            return
        }
        settleWithLateBeat()
    }

    /// Whether the page has laid out at all: a view on screen whose content has width.
    /// The scroll view reports zero by zero until the first layout, and a capture taken
    /// against that shows nothing.
    private func contentHasLaidOut() -> Bool {
        guard let found = onScreenWebView() else { return false }
        return found.view.scrollView.contentSize.width > 0
    }

    /// Waits, bounded, for the page's first layout, then settles on it. The wait replaces
    /// the retry ladder for this case: a not-ready page is not a failed capture, so it
    /// owes no rung.
    private func watchForLayout() {
        guard layoutWatch == nil else { return }
        SnapshotLog.event("layout watch start \(logTag)")
        layoutWatch = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.layoutWatchLimit
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                if self.contentHasLaidOut() {
                    self.layoutWatch = nil
                    SnapshotLog.event("layout landed \(self.logTag)")
                    self.settleWithLateBeat()
                    return
                }
            }
            guard let self else { return }
            self.layoutWatch = nil
            SnapshotLog.event("layout watch gave up \(self.logTag)")
        }
    }

    /// The page's title landed.
    func titleKnown() {
        onPageTitled?()
    }

    /// The web view SwiftUI built for this page, kept by the reading screen's probe.
    /// Weak, because the hierarchy owns the view.
    @ObservationIgnored var webView: WKWebView?
    /// The probe's own walk to that view, retried at capture time — the view can be
    /// built after the probe first looks, and swapped for a new one later.
    @ObservationIgnored var webViewLookup: (@MainActor () -> WKWebView?)?

    /// The screen measured the page area. A session with no view on screen — its tab
    /// left — takes the size whatever it had: its captures are the page's own export,
    /// which wants the region the page shows at with nothing covering it. A smaller
    /// size is a cover still on it — the sheet, the keyboard — and never replaces a
    /// truer one.
    func noteViewport(_ size: CGSize) {
        guard onScreenWebView() == nil else { return }
        if let current = viewportSize, size.height < current.height { return }
        guard viewportSize != size else { return }
        viewportSize = size
    }

    /// The reading screen went away: the page's view leaves the hierarchy, so its
    /// handle is dropped — a detached view held alive keeps its accessibility line open,
    /// which has been seen to wedge the app's accessibility snapshot — and its focus
    /// goes with it. The layout watch waits on a view that is leaving, so it stops. The
    /// probe re-finds the view when the page returns to the screen.
    func screenWentAway() {
        layoutWatch?.cancel()
        layoutWatch = nil
        webView?.endEditing(true)
        webView = nil
    }

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

    init(url: URL, pageConfiguration: WebPage.Configuration? = nil) {
        initialURL = url
        requestedURL = url
        page = pageConfiguration.map { WebPage(configuration: $0) } ?? WebPage()
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
        const icon = document.querySelector("link[rel~='icon']")
            || document.querySelector("link[rel='apple-touch-icon']");
        return icon ? icon.href : new URL("/favicon.ico", location.href).href;
        """#

    /// Starts the session: the first load, then the standing watch on navigation events.
    /// The watch subscribes after the load is issued, and a page served fast can outrun
    /// it — the load's own sequence, in `drive`, spans every event of that load.
    func run() async {
        SnapshotLog.event("observer start \(logTag)")
        open(initialURL)
        while !Task.isCancelled {
            do {
                for try await event in page.navigations {
                    SnapshotLog.event(
                        "nav \(logTag) \(Self.describe(event)) url=\(page.url?.absoluteString ?? "nil")")
                    if event == .committed {
                        failure = nil
                    }
                    if event == .finished {
                        await refreshPageBackground()
                        await readPageIcon()
                        settle()
                    }
                }
                SnapshotLog.event("nav \(logTag) sequence ended")
                return
            } catch is CancellationError {
                return
            } catch {
                SnapshotLog.event("nav \(logTag) threw \(Self.describe(error))")
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
        SnapshotLog.event("load \(logTag) \(requestedURL?.absoluteString ?? "nil")")
        let sequence = events()
        loadTask = Task { [weak self] in
            await self?.drive(sequence)
        }
        watchLoad()
    }

    /// Watches the page itself, not its event streams, until the load is done: no longer
    /// loading, with a URL and no failure. Then the page settles — the tab takes its
    /// title and its picture — whether or not the page is on screen, and whether or not
    /// either navigation stream reported the end. The page's own export paints with no
    /// view, so a tab left the moment its address was submitted still gets its picture.
    private func watchLoad() {
        loadWatch?.cancel()
        loadWatch = Task { [weak self] in
            try? await Task.sleep(for: Self.loadWatchStart)
            let deadline = ContinuousClock.now + Self.loadWatchLimit
            while ContinuousClock.now < deadline {
                guard !Task.isCancelled, let self else { return }
                if self.failure != nil { return }
                if !self.page.isLoading, self.page.url != nil {
                    SnapshotLog.event(
                        "load done \(self.logTag) progress=\(self.page.estimatedProgress) "
                            + "url=\(self.page.url?.absoluteString ?? "nil")")
                    self.loadWatch = nil
                    // A first load can finish before the navigation watch subscribes;
                    // the page colour and icon are read here too.
                    await self.refreshPageBackground()
                    await self.readPageIcon()
                    self.settle()
                    return
                }
                try? await Task.sleep(for: Self.loadWatchInterval)
            }
            guard let self else { return }
            self.loadWatch = nil
            SnapshotLog.event(
                "load watch gave up \(self.logTag) loading=\(self.page.isLoading) "
                    + "progress=\(self.page.estimatedProgress) "
                    + "url=\(self.page.url?.absoluteString ?? "nil")")
        }
    }

    /// Observes one load: a throw is the page failing to load. The load's own sequence
    /// ends when the load does, so that end settles the page even when the session-wide
    /// watch — subscribed after the load was issued — saw none of it.
    private func drive<Events: AsyncSequence>(_ events: Events) async
    where Events.Element == WebPage.NavigationEvent, Events.Failure == Error {
        do {
            for try await _ in events {}
            SnapshotLog.event("load finished \(logTag)")
            settle()
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
    /// page that misses both windows reads as a miss, and a late answer is dropped. A
    /// page with no view on screen — a tab left the moment its address was submitted — is
    /// captured by the page's export alone, once its load has settled; a page with no
    /// layout yet is not ready, held for the layout watch rather than spent on the retry
    /// ladder. Every step is logged, because the captures are being diagnosed on the
    /// simulator.
    func snapshot(trigger: String, offScreenAllowed: Bool = true) async -> CaptureOutcome {
        let start = ContinuousClock.now
        guard failure == nil, page.url != nil else {
            SnapshotLog.event(
                "\(trigger) skip failure=\(failure != nil) url=\(page.url?.absoluteString ?? "nil")")
            return .miss
        }
        guard let size = viewportSize else {
            SnapshotLog.event("\(trigger) skip viewport=nil")
            return .miss
        }
        // A capture taken mid-load is a picture of a blank page: hold it for the load's
        // end, which settles again.
        guard !page.isLoading else {
            SnapshotLog.event("\(trigger) notReady loading progress=\(page.estimatedProgress)")
            return .notReady
        }
        // The region is the remembered viewport; the view's bounds and its scroll view's
        // content size are what the page actually laid out at — logged together so a
        // picture that crops says which two disagreed. A page with no view is off
        // screen: one that has settled carries its picture inside it, and the page's own
        // export paints without a view; one still on its way is held.
        let found = onScreenWebView()
        if let found {
            let scroll = found.view.scrollView
            guard scroll.contentSize.width > 0 else {
                SnapshotLog.event(
                    "\(trigger) notReady region=\(Int(size.width))x\(Int(size.height)) view="
                        + "\(Int(found.view.bounds.width))x\(Int(found.view.bounds.height))"
                        + " content=\(Int(scroll.contentSize.width))x\(Int(scroll.contentSize.height))"
                )
                return .notReady
            }
            SnapshotLog.event(
                "\(trigger) capture region=\(Int(size.width))x\(Int(size.height)) view="
                    + "\(Int(found.view.bounds.width))x\(Int(found.view.bounds.height))"
                    + " content=\(Int(scroll.contentSize.width))x\(Int(scroll.contentSize.height))"
            )
        } else {
            guard hasSettled, offScreenAllowed, isDrawnUnseen else {
                SnapshotLog.event(
                    "\(trigger) notReady view=none settled=\(hasSettled) "
                        + "allowed=\(offScreenAllowed) drawn=\(isDrawnUnseen)")
                return .notReady
            }
            // Drawn unseen, the page can still be laid out at the width it had on its
            // way out — the card's, mid-transition. Its picture waits until the page
            // has laid itself out at the screen's own width again.
            guard await layoutWidthMatches(size.width) else {
                SnapshotLog.event("\(trigger) notReady width settling")
                return .miss
            }
            SnapshotLog.event(
                "\(trigger) capture region=\(Int(size.width))x\(Int(size.height)) view=none settled")
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
            return .stored(data)
        }
        if let error = exportThrown.error {
            SnapshotLog.event(
                "\(trigger) export nil \(Self.ms(since: start))ms error=\(Self.describe(error))")
        } else {
            SnapshotLog.event("\(trigger) export nil \(Self.ms(since: start))ms")
        }
        // Off screen there is no view to fall back to: the page's export was the one
        // shot at its picture.
        guard let found else { return .miss }
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
        return data.map(CaptureOutcome.stored) ?? .miss
    }

    /// Waits, briefly, for the page's own layout width to be the given width.
    private func layoutWidthMatches(_ width: CGFloat) async -> Bool {
        let deadline = ContinuousClock.now + Self.widthWait
        while ContinuousClock.now < deadline {
            if let result = try? await page.callJavaScript(
                "return window.innerWidth", contentWorld: .defaultClient),
                let inner = (result as? NSNumber)?.doubleValue,
                abs(inner - Double(width)) < 1
            {
                // The layout is right; the drawing lags it. Let the page repaint at the
                // new width before its picture is taken.
                try? await Task.sleep(for: Self.repaintWait)
                return true
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    private static let widthWait: Duration = .milliseconds(2_000)
    private static let repaintWait: Duration = .milliseconds(500)

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

    /// A navigation event, named for the log — a page that never paints says which
    /// moments it reached.
    private static func describe(_ event: WebPage.NavigationEvent) -> String {
        if event == .committed { return "committed" }
        if event == .finished { return "finished" }
        return String(describing: event)
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
    /// How long a held capture waits for the page's first layout before giving up.
    private static let layoutWatchLimit: Duration = .seconds(15)
    /// The load watch: a beat for the load to begin, then a look every interval, up to
    /// the limit.
    private static let loadWatchStart: Duration = .milliseconds(250)
    private static let loadWatchInterval: Duration = .milliseconds(200)
    private static let loadWatchLimit: Duration = .seconds(90)
}

extension ReadingSession: Hashable {

    /// Identity: the screen's change triggers compare sessions by who they are.
    nonisolated static func == (lhs: ReadingSession, rhs: ReadingSession) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
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
