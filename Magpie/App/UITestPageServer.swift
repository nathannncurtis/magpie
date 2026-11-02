import Foundation
import Network

/// The UI tests' own pages, served from inside the app over the loopback interface, so a
/// flow never leaves the device.
final class UITestPageServer: @unchecked Sendable {

    static let shared = UITestPageServer()

    private let queue = DispatchQueue(label: "com.magpiebrowser.uitest.pageserver")
    private var listener: NWListener?

    /// Starts serving, and returns once the port is listening or the wait runs out. A
    /// relaunched app finds the port still held by the last run's closed connections, so
    /// the address is reused and a failed bind tries again; the first page of a relaunch
    /// is requested moments after this returns, and must find the server there.
    func start() async {
        guard listener == nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = ReadyGate(continuation)
            queue.async { self.listen(gate: gate, attempt: 0) }
            queue.asyncAfter(deadline: .now() + Self.readyWait) { gate.open() }
        }
    }

    private static let readyWait: TimeInterval = 3
    private static let rebindDelay: TimeInterval = 0.2
    private static let rebindAttempts = 15

    private func listen(gate: ReadyGate, attempt: Int) {
        guard let port = NWEndpoint.Port(rawValue: UITestEnvironment.pageServerPort) else {
            gate.open()
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: port) else {
            SnapshotLog.event("server listener attempt=\(attempt) create failed")
            retry(gate: gate, attempt: attempt)
            return
        }
        listener.newConnectionHandler = { connection in
            SnapshotLog.event("server connection \(connection.endpoint)")
            connection.stateUpdateHandler = { state in
                SnapshotLog.event("server connection state \(state)")
            }
            connection.start(queue: self.queue)
            self.serve(connection)
        }
        listener.stateUpdateHandler = { state in
            SnapshotLog.event("server listener attempt=\(attempt) state=\(state)")
            switch state {
            case .ready:
                gate.open()
            case .failed, .waiting:
                listener.cancel()
                if self.listener === listener { self.listener = nil }
                self.retry(gate: gate, attempt: attempt)
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func retry(gate: ReadyGate, attempt: Int) {
        guard attempt < Self.rebindAttempts else {
            gate.open()
            return
        }
        queue.asyncAfter(deadline: .now() + Self.rebindDelay) {
            self.listen(gate: gate, attempt: attempt + 1)
        }
    }

    /// One request, one reply, one closed connection.
    private func serve(_ connection: NWConnection) {
        receiveHead(of: connection, buffer: Data())
    }

    /// Reads the request as a stream until its head ends. A message receive has no
    /// boundary to find in TCP — it waits for the peer to close, so a client that keeps
    /// the connection open for its reply never gets one.
    private func receiveHead(of connection: NWConnection, buffer: Data) {
        let headEnd = Data("\r\n\r\n".utf8)
        if buffer.range(of: headEnd) != nil || buffer.count > 16 * 1024 {
            let reply = self.reply(to: buffer)
            SnapshotLog.event("server reply \(Self.route(of: buffer)) \(reply.count)B")
            connection.send(
                content: reply,
                completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
            guard error == nil, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            self.receiveHead(of: connection, buffer: buffer + data)
        }
    }

    /// Hands the start its answer once: the port listening, or the wait over.
    private final class ReadyGate: @unchecked Sendable {
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        /// Called only on the server's queue.
        func open() {
            continuation?.resume()
            continuation = nil
        }
    }

    /// The full HTTP reply for one request's bytes.
    private func reply(to request: Data) -> Data {
        let route = Self.route(of: request)
        let page = Self.page(for: route)
        let head = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(Self.contentType(for: route)); charset=utf-8",
            "Content-Length: \(page.utf8.count)",
            "Connection: close",
        ].joined(separator: "\r\n")
        var reply = Data((head + "\r\n\r\n").utf8)
        reply.append(Data(page.utf8))
        return reply
    }

    /// The path of the request line, "/..." or "/" when nothing parses.
    private static func route(of request: Data) -> String {
        let head = String(decoding: request.prefix(8 * 1024), as: UTF8.self)
        guard
            let line = head.split(separator: "\r\n").first,
            let path = line.split(separator: " ").dropFirst().first
        else { return "/" }
        return path.split(separator: "?").first.map(String.init) ?? "/"
    }

    /// The page a route serves; the block's colour tells the routes apart.
    private static func page(for route: String) -> String {
        switch route {
        case "/search":
            return shell(title: "magpie test", path: route, block: "#B3410C")
        case "/page":
            return shell(title: "magpie test page", path: route, block: "#2B62C2")
        case "/mode":
            return modeProbe
        case "/mod.user.js":
            return UITestModFixtures.userscript
        case "/mod.list.txt":
            return UITestModFixtures.filterList
        default:
            return shell(title: "magpie test", path: route, block: "#2B8A5A")
        }
    }

    /// A page that says which version of itself it loaded: "mode: desktop" when the
    /// browser identifies as a computer, "mode: mobile" otherwise.
    private static let modeProbe = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>magpie test mode</title>
        </head>
        <body>
        <h1 id="mode">mode: loading</h1>
        <script>
        document.getElementById("mode").textContent =
            /Macintosh/.test(navigator.userAgent) ? "mode: desktop" : "mode: mobile";
        </script>
        </body>
        </html>
        """

    /// What each route serves; mods' files are not pages.
    private static func contentType(for route: String) -> String {
        switch route {
        case "/mod.user.js":
            return "text/javascript"
        case "/mod.list.txt":
            return "text/plain"
        default:
            return "text/html"
        }
    }

    /// A page that follows the appearance, so the flow's shots read under both. Its
    /// content is loud — the route as a banner over a colour block — so a capture is
    /// unmistakable in the shots and a blank one cannot hide.
    private static func shell(title: String, path: String, block: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(title)</title>
        <link rel="icon" href="/icon.png">
        <style>
        body { margin: 0; padding: 24px; min-height: 100vh; font: -apple-system-body;
        background: #F5F3EE; color: #26221C; }
        @media (prefers-color-scheme: dark) {
        body { background: #17181A; color: #F2F2EE; } }
        h1 { font-size: 44px; line-height: 1.1; margin: 0; }
        .block { height: 110px; border-radius: 14px; margin-top: 16px; background: \(block); }
        p { font-size: 17px; line-height: 1.5; margin: 16px 0 0; }
        </style>
        </head>
        <body>
        <h1>\(path)</h1>
        <div class="block"></div>
        <p>This page is served from inside the app, over the loopback interface.</p>
        <p>It stands in for the open web while the interface is exercised end to end.</p>
        <p>The heading and the block carry the route, so a capture reads at a glance.</p>
        </body>
        </html>
        """
    }
}
