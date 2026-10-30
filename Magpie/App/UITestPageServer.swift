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

    /// The page a route serves; unknown routes get a plain one.
    private static func page(for route: String) -> String {
        switch route {
        case "/search":
            return shell(title: "magpie test", heading: "magpie test")
        case "/page":
            return shell(title: "magpie test page", heading: "magpie test page")
        default:
            return shell(title: "magpie test", heading: "")
        }
    }

    /// A page that follows the appearance, so the flow's shots read under both.
    private static func shell(title: String, heading: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <link rel="icon" href="/icon.png">
        <style>
        body { margin: 0; min-height: 100vh; display: grid; place-content: center;
        font: -apple-system-body; background: #F5F3EE; color: #26221C; }
        @media (prefers-color-scheme: dark) {
        body { background: #17181A; color: #F2F2EE; } }
        h1 { font-size: 30px; }
        </style>
        </head>
        <body><h1>\(heading)</h1></body>
        </html>
        """
    }
}
