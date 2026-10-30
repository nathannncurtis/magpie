import Foundation
import Testing

@testable import Magpie

/// The run's state machine, with every piece stubbed: find, read, compose —
/// and each way a run stops without a page.
@Suite("SkimRun")
@MainActor
struct SkimRunTests {

    private var engine: SearchEngine {
        SearchEngine(
            id: "test", displayName: "Test", searchTemplate: "https://test.example/?q=%s",
            suggestTemplate: nil, suggestFormat: nil)
    }

    private func makeRun(links: [URL]?, reader: StubReader, composer: StubComposer) -> SkimRun {
        SkimRun(
            query: "seasoning",
            engine: engine,
            dependencies: SkimDependencies(
                finder: StubFinder(links: links), reader: reader, composer: composer))
    }

    /// Waits for the condition, handing the main actor back between checks.
    private func eventually(
        timeout: TimeInterval = 2, _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    private func isWorking(readCount: Int, on run: SkimRun) -> Bool {
        if case .working(let progress) = run.state {
            return progress.readCount == readCount
        }
        return false
    }

    private func isFinished(on run: SkimRun) -> Bool {
        if case .finished = run.state { return true }
        return false
    }

    private func hasFailed(on run: SkimRun) -> Bool {
        if case .failed = run.state { return true }
        return false
    }

    // MARK: A run that works

    @Test("a run reads its first three sources and lands on a finished page")
    func startReadsThreeAndComposes() async {
        let gate = Gate()
        let composer = StubComposer(gates: [gate]) { sources in
            builtPage(query: "seasoning", sources: sources)
        }
        let reader = StubReader { url in readPage(url, title: "Page \(url.path)") }
        let run = makeRun(links: resultLinks(10), reader: reader, composer: composer)

        run.start()

        // The working screen's facts: three hosts planned, all three read.
        let sawReading = await eventually {
            if case .working(let progress) = run.state {
                return progress.readCount == 3
                    && progress.plannedCount == 3
                    && progress.plannedHosts == ["a.example", "b.example", "c.example"]
            }
            return false
        }
        #expect(sawReading)

        await gate.open()
        #expect(await eventually { isFinished(on: run) })

        let calls = await composer.calls
        #expect(calls.map { $0.count } == [3])
        #expect(calls[0].map(\.url) == Array(resultLinks(10).prefix(3)))
        #expect(run.page?.sources.count == 3)
        #expect(run.page?.canDigDeeper == true)
        #expect(await reader.readURLs.count == 3)
    }

    @Test("a run with no results fails on the engine's line")
    func noResultsFails() async {
        let composer = StubComposer { sources in builtPage(query: "seasoning", sources: sources) }
        let reader = StubReader { _ in nil }
        let run = makeRun(links: nil, reader: reader, composer: composer)

        run.start()

        #expect(await eventually { hasFailed(on: run) })
        #expect(run.failure?.line == SkimFailureLines.engineDown)
    }

    // MARK: A run that stops short

    @Test("a run that cannot read two pages fails with the board's line")
    func tooFewFails() async {
        let composer = StubComposer { sources in builtPage(query: "seasoning", sources: sources) }
        let reader = StubReader { url in url.path == "/one" ? readPage(url, title: "One") : nil }
        let run = makeRun(links: resultLinks(3), reader: reader, composer: composer)

        run.start()

        #expect(await eventually { hasFailed(on: run) })
        #expect(run.failure?.line == SkimFailureLines.tooFew(read: 1, attempted: 3))
    }

    @Test("a refusal fails on the refused line")
    func refusalFails() async {
        let composer = StubComposer { _ in throw ComposeStub.refusal }
        let reader = StubReader { url in readPage(url, title: "Page \(url.path)") }
        let run = makeRun(links: resultLinks(3), reader: reader, composer: composer)

        run.start()

        #expect(await eventually { hasFailed(on: run) })
        #expect(run.failure?.line == SkimFailureLines.refused)
    }

    @Test("cancel stops the run where it stands")
    func cancelStops() async {
        let gate = Gate()
        let composer = StubComposer(gates: [gate]) { sources in
            builtPage(query: "seasoning", sources: sources)
        }
        let reader = StubReader { url in readPage(url, title: "Page \(url.path)") }
        let run = makeRun(links: resultLinks(3), reader: reader, composer: composer)

        run.start()
        #expect(await eventually { isWorking(readCount: 3, on: run) })

        run.cancel()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(100))

        var stillWorking = false
        if case .working = run.state { stillWorking = true }
        #expect(stillWorking)
        #expect(run.page == nil)
        #expect(run.failure == nil)
    }

    // MARK: Dig deeper

    @Test("dig deeper reads on to ten sources and composes again")
    func digDeeperReachesTen() async {
        let first = Gate()
        let second = Gate()
        let composer = StubComposer(gates: [first, second]) { sources in
            builtPage(query: "seasoning", sources: sources)
        }
        let reader = StubReader { url in readPage(url, title: "Page \(url.path)") }
        let run = makeRun(links: resultLinks(12), reader: reader, composer: composer)

        run.start()
        await first.open()
        #expect(await eventually { isFinished(on: run) })

        run.digDeeper()

        let sawTenRead = await eventually {
            if case .working(let progress) = run.state {
                return progress.readCount == 10 && progress.plannedCount == 10
            }
            return false
        }
        #expect(sawTenRead)

        await second.open()
        #expect(await eventually(timeout: 5) { isFinished(on: run) })

        let calls = await composer.calls
        #expect(calls.map { $0.count } == [3, 10])
        #expect(run.page?.sources.count == 10)
        #expect(run.page?.canDigDeeper == false)

        // Ten is the end of it: the control has nothing left to read.
        run.digDeeper()
        #expect(await composer.calls.count == 2)
    }

    @Test("a deeper page that cannot be built leaves the standing one")
    func digDeeperFailureKeepsThePage() async {
        let first = Gate()
        let second = Gate()
        let composer = StubComposer(gates: [first, second]) { sources in
            guard sources.count <= 3 else { throw ComposeStub.failed }
            return builtPage(query: "seasoning", sources: sources)
        }
        let reader = StubReader { url in readPage(url, title: "Page \(url.path)") }
        let run = makeRun(links: resultLinks(8), reader: reader, composer: composer)

        run.start()
        await first.open()
        #expect(await eventually { isFinished(on: run) })
        let standing = run.page

        run.digDeeper()
        #expect(await eventually(timeout: 5) { await composer.calls.count == 2 })
        await second.open()
        try? await Task.sleep(for: .milliseconds(150))

        #expect(isFinished(on: run))
        #expect(run.page == standing)
        #expect(run.page?.sources.count == 3)
    }

    // MARK: Landing

    @Test("a landed state stands as the run's own")
    func landedStateStands() {
        let reader = StubReader { _ in nil }
        let composer = StubComposer { sources in builtPage(query: "seasoning", sources: sources) }
        let run = makeRun(links: nil, reader: reader, composer: composer)
        let page = builtPage(
            query: "seasoning", sources: [readPage(resultLinks(1)[0], title: "One")])

        run.land(.finished(page))
        #expect(run.page == page)
        #expect(run.failure == nil)

        run.land(.failed(SkimFailure(line: SkimFailureLines.generic)))
        #expect(run.page == nil)
        #expect(run.failure?.line == SkimFailureLines.generic)
    }
}

// MARK: - Stubs

/// A finder that hands back a fixed page of links.
private struct StubFinder: ResultFinding {
    var links: [URL]?

    func topResultLinks(query: String, engine: SearchEngine) async -> [URL]? {
        links
    }
}

/// A reader that answers from a fixed rule, remembering what it was asked.
private actor StubReader: PageReading {
    private let readable: @Sendable (URL) -> ReadPage?
    private(set) var readURLs: [URL] = []

    init(readable: @escaping @Sendable (URL) -> ReadPage?) {
        self.readable = readable
    }

    func read(_ url: URL) -> ReadPage? {
        readURLs.append(url)
        return readable(url)
    }
}

/// A composer the test can hold at gates, one per call.
private actor StubComposer: SkimComposing {
    private let build: @Sendable ([ReadPage]) throws -> SkimPage
    private let gates: [Gate]
    private(set) var calls: [[ReadPage]] = []

    init(
        gates: [Gate] = [], build: @escaping @Sendable ([ReadPage]) throws -> SkimPage
    ) {
        self.gates = gates
        self.build = build
    }

    func compose(query: String, sources: [ReadPage]) async throws -> SkimPage {
        calls.append(sources)
        if !gates.isEmpty {
            await gates[min(calls.count - 1, gates.count - 1)].wait()
        }
        return try build(sources)
    }
}

/// Holds one composer call until the test lets it through.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiter in
            waiters.append(waiter)
        }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// The shape of a thrown compose error, without naming the framework's enums.
private enum ComposeStub: Error {
    case refusal
    case failed
}

// MARK: - Fixed material

private func resultLinks(_ count: Int) -> [URL] {
    (0..<count).map { index in
        let host = String(UnicodeScalar(97 + index)!)
        let path = index == 0 ? "one" : String(index)
        return URL(string: "https://\(host).example/\(path)")!
    }
}

private func readPage(_ url: URL, title: String) -> ReadPage {
    ReadPage(
        url: url, title: title, siteName: "", faviconURL: nil, imageURL: nil,
        text: "Readable text, long enough to stand in for an article.")
}

private func builtPage(query: String, sources: [ReadPage]) -> SkimPage {
    SkimPage(
        query: query,
        title: "A skim page",
        sections: [
            SkimSection(emoji: "🔥", term: "Method", claim: "One plain sentence.", citations: [1])
        ],
        sources: sources.map { source in
            SkimSourceRef(
                url: source.url, title: source.title, host: source.host,
                faviconURL: nil, imageURL: nil)
        })
}
