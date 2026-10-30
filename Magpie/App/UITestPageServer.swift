import Foundation
import Network

/// The UI tests' own pages, served from inside the app over the loopback interface, so a
/// flow never leaves the device.
final class UITestPageServer: @unchecked Sendable {

    static let shared = UITestPageServer()

    private let queue = DispatchQueue(label: "com.magpiebrowser.uitest.pageserver")
    private var listener: NWListener?

    /// Starts serving. A second start does nothing; a taken port leaves the flow to fail.
    func start() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: UITestEnvironment.pageServerPort) else {
            return
        }
        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                self.serve(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            return
        }
    }

    /// One request, one reply, one closed connection.
    private func serve(_ connection: NWConnection) {
        connection.receiveMessage { data, _, _, error in
            guard error == nil else {
                connection.cancel()
                return
            }
            let reply = self.reply(to: data ?? Data())
            connection.send(
                content: reply,
                completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// The full HTTP reply for one request's bytes.
    private func reply(to request: Data) -> Data {
        let page = Self.page(for: Self.route(of: request))
        let head = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
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
        default:
            return shell(title: "magpie test", path: route, block: "#2B8A5A")
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
