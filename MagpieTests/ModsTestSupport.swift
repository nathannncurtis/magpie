import Foundation

@testable import Magpie

/// One reply a stub fetch serves: bytes with a 200, a bare status, or nothing at all.
enum StubReply {

    case ok(String)
    case status(Int)
    case offline

    func download() throws -> ModDownload {
        switch self {
        case .ok(let text):
            return ModDownload(data: Data(text.utf8), response: http(200))
        case .status(let code):
            return ModDownload(data: Data(), response: http(code))
        case .offline:
            throw URLError(.notConnectedToInternet)
        }
    }

    private func http(_ statusCode: Int) -> HTTPURLResponse {
        let address = URL(fileURLWithPath: "/reply")
        guard
            let response = HTTPURLResponse(
                url: address, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            preconditionFailure("A stand-in reply could not be made")
        }
        return response
    }
}

/// A fetch that answers from a table, so the mods' network paths run without a network.
/// Each reply is keyed by the address's file name; "*" answers anything.
final class StubModFetch: @unchecked Sendable {

    private let lock = NSLock()
    private let replies: [String: StubReply]
    private var requested: [String] = []

    init(replies: [String: StubReply] = [:]) {
        self.replies = replies
    }

    func call(_ url: URL) async throws -> ModDownload {
        let path = url.lastPathComponent
        let reply = lock.withLock {
            requested.append(path)
            return replies[path] ?? replies["*"]
        }
        guard let reply else { throw URLError(.badURL) }
        return try reply.download()
    }

    var requestedPaths: [String] {
        lock.withLock { requested }
    }

    var callCount: Int {
        lock.withLock { requested.count }
    }
}

/// A clock a test can move, for the directory's once-a-day fetch policy.
final class TestClock: @unchecked Sendable {

    private let lock = NSLock()
    private var instant: Date

    init(_ instant: Date = Date()) {
        self.instant = instant
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { instant = instant.addingTimeInterval(interval) }
    }

    func now() -> Date {
        lock.withLock { instant }
    }
}
