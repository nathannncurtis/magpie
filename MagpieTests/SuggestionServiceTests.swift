import Foundation
import Testing

@testable import Magpie

/// Serves canned suggest responses and records what was asked.
final class CannedSuggestProtocol: URLProtocol {

    private struct Store {
        var bodies: [String: Result<Data, URLError>] = [:]
        var requests: [(url: String, at: Date)] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var store = Store()

    /// Serves `body` for any URL whose query contains `marker`.
    static func serve(_ marker: String, body: String) {
        let data = Data(body.utf8)
        lock.lock()
        defer { lock.unlock() }
        store.bodies[marker] = .success(data)
    }

    static func fail(_ marker: String) {
        lock.lock()
        defer { lock.unlock() }
        store.bodies[marker] = .failure(URLError(.timedOut))
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return store.requests.count
    }

    static var requestedURLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return store.requests.map(\.url)
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        store = Store()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let marker = Self.marker(in: url)
        let body: Result<Data, URLError>
        if let marker, let canned = Self.canned(marker) {
            body = canned
        } else {
            body = .failure(URLError(.badServerResponse))
        }
        Self.record(url: url)
        switch body {
        case .success(let data):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func marker(in url: String) -> String? {
        store.bodies.keys.first { url.contains($0) }
    }

    private static func canned(_ marker: String) -> Result<Data, URLError>? {
        store.bodies[marker]
    }

    private static func record(url: String) {
        store.requests.append((url, Date()))
    }
}

@Suite("SuggestionService", .serialized)
struct SuggestionServiceTests {

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedSuggestProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func service(debounce: Duration = .milliseconds(20)) -> SuggestionService {
        SuggestionService(debounce: debounce, maxRows: 3, session: session())
    }

    init() {
        CannedSuggestProtocol.reset()
    }

    // MARK: Response shapes

    @Test(
        "OpenSearch list responses parse",
        arguments: [
            (
                Data(
                    """
                    ["cars",["cars","cars for sale","cars movie"]]
                    """.utf8), ["cars", "cars for sale", "cars movie"]
            ),
            (
                Data(
                    """
                    ["seasoning car",["seasoning carbon steel","seasoning cast iron","carbon steel vs cast iron","seasoning pan"]]
                    """.utf8),
                ["seasoning carbon steel", "seasoning cast iron", "carbon steel vs cast iron", "seasoning pan"]
            ),
        ])
    func parsesOpenSearchList(data: Data, expected: [String]) {
        #expect(SuggestionService.parse(data, format: .openSearchList) == expected)
    }

    @Test("phrase responses parse")
    func parsesPhrases() {
        let data = Data(#"[{"phrase":"cars.com"},{"phrase":"cars for sale"}]"#.utf8)
        #expect(SuggestionService.parse(data, format: .phrases) == ["cars.com", "cars for sale"])
    }

    @Test("titled responses parse")
    func parsesTitled() {
        let data = Data(
            #"""
            [{"t":"cars for sale","txt":null},{"t":"cars movie","txt":"2006 film","k":"kagi"}]
            """#.utf8)
        #expect(SuggestionService.parse(data, format: .titled) == ["cars for sale", "cars movie"])
    }

    @Test("garbage reads as no rows")
    func garbageIsQuiet() {
        #expect(SuggestionService.parse(Data("".utf8), format: .openSearchList) == [])
        #expect(SuggestionService.parse(Data("<html>302</html>".utf8), format: .openSearchList) == [])
        #expect(SuggestionService.parse(Data("[]".utf8), format: .phrases) == [])
        #expect(SuggestionService.parse(Data("{}".utf8), format: .titled) == [])
        #expect(SuggestionService.parse(Data("[\"only a query\"]".utf8), format: .openSearchList) == [])
    }

    // MARK: Fetching

    @Test("an end-to-end fetch caps, drops echoes and duplicates")
    func fetchRows() async {
        CannedSuggestProtocol.serve(
            "type=list",
            body: """
                ["seasoning car",["seasoning car","seasoning carbon steel","SEASONING cast iron","seasoning cast iron","seasoning pan","seasoning wok"]]
                """)
        let rows = await service().suggestions(
            for: "seasoning car", engine: .default, enabled: true)
        #expect(rows == ["seasoning carbon steel", "SEASONING cast iron", "seasoning pan"])
    }

    @Test("disabled, empty and endpoint-less input asks for nothing")
    func quietPaths() async {
        CannedSuggestProtocol.serve("type=list", body: #"["x",["x"]"#)
        let ecosia = SearchEngine.builtins[4]
        #expect(await service().suggestions(for: "cars", engine: ecosia, enabled: true) == [])
        #expect(await service().suggestions(for: "cars", engine: .default, enabled: false) == [])
        #expect(await service().suggestions(for: "   ", engine: .default, enabled: true) == [])
        #expect(CannedSuggestProtocol.requestCount == 0)
    }

    @Test("a failed request comes back as no rows")
    func failureIsQuiet() async {
        CannedSuggestProtocol.fail("type=list")
        let rows = await service().suggestions(for: "cars", engine: .default, enabled: true)
        #expect(rows == [])
    }

    @Test("the request waits out the debounce before it is sent")
    func debounceDelays() async {
        CannedSuggestProtocol.serve("type=list", body: #"["cars",["cars for sale"]]"#)
        let started = Date()
        _ = await service(debounce: .milliseconds(150)).suggestions(
            for: "cars", engine: .default, enabled: true)
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed >= 0.14, "request left before the debounce settled")
        #expect(CannedSuggestProtocol.requestCount == 1)
    }

    @Test("a superseded call is cancelled and never asks")
    func cancelledCallAsksNothing() async {
        CannedSuggestProtocol.serve("type=list", body: #"["cars",["cars for sale"]]"#)
        let task = Task {
            await service(debounce: .milliseconds(500)).suggestions(
                for: "cars", engine: .default, enabled: true)
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let rows = await task.value
        #expect(rows == [])
        #expect(CannedSuggestProtocol.requestCount == 0, "a cancelled call still reached the network")
    }

    @Test("the session carries no cookies and gives up quickly")
    func sessionHygiene() {
        let configuration = SuggestionService.configuration
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.timeoutIntervalForRequest <= 5)
        #expect(configuration.timeoutIntervalForResource <= 8)
    }
    @Test("typing on cancels each earlier keystroke; only the settled text is asked for")
    func typingCancelsEarlierKeystrokes() async {
        CannedSuggestProtocol.serve("q=", body: #"["carb",["carbon steel"]]"#)
        let service = service(debounce: .milliseconds(200))
        var earlier: [Task<[String], Never>] = []
        for prefix in ["c", "ca", "car"] {
            earlier.last?.cancel()
            earlier.append(Task { await service.suggestions(for: prefix, engine: .default, enabled: true) })
            try? await Task.sleep(for: .milliseconds(40))
        }
        earlier.last?.cancel()
        let settled = await service.suggestions(for: "carb", engine: .default, enabled: true)
        for task in earlier {
            #expect(await task.value == [])
        }
        #expect(settled == ["carbon steel"])
        #expect(CannedSuggestProtocol.requestCount == 1)
        #expect(CannedSuggestProtocol.requestedURLs == ["https://duckduckgo.com/ac/?q=carb&type=list"])
    }

    @Test("suggestions off never reaches the network, however long the wait")
    func disabledNeverSends() async {
        CannedSuggestProtocol.serve("q=", body: #"["cars",["cars for sale"]]"#)
        for engine in SearchEngine.builtins {
            let rows = await service(debounce: .milliseconds(1)).suggestions(
                for: "cars", engine: engine, enabled: false)
            #expect(rows == [])
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(CannedSuggestProtocol.requestCount == 0)
    }

    @Test("the suggest request carries the trimmed, encoded query")
    func suggestRequestEncoding() async {
        CannedSuggestProtocol.serve("q=", body: #"["x",[]]"#)
        _ = await service().suggestions(for: "  a+b & c#d 100%  ", engine: .default, enabled: true)
        #expect(
            CannedSuggestProtocol.requestedURLs
                == ["https://duckduckgo.com/ac/?q=a%2Bb%20%26%20c%23d%20100%25&type=list"])
    }
}
