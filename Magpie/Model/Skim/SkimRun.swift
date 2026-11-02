import Foundation
import Observation

/// How far a Skim run has got.
struct SkimProgress: Equatable {
    /// The hosts of the pages this run plans to read; their favicons fill in as
    /// each one lands.
    var plannedHosts: [String] = []
    /// How many of them have been read.
    var readCount: Int = 0
    /// The count the working line names.
    var plannedCount: Int = SkimPage.initialSourceCount
}

/// Why a run stopped without a page. One line, in the app's voice (06).
struct SkimFailure: Equatable {
    var line: String
}

/// The failure lines. The boards carry the first; the rest are drafted.
enum SkimFailureLines {

    static func tooFew(read: Int, attempted: Int) -> String {
        String(localized: "Only \(read) of \(attempted) pages could be read. That's not enough to Skim.")
    }

    static let refused = String(localized: "Couldn't put those pages together. Try again.")
    static let tooLong = String(localized: "Those pages are too long to read together. Try a narrower search.")
    static let engineDown = String(
        localized: "Search results didn't load. Check your connection and try again.")
    static let generic = String(localized: "That didn't work. Try again.")

    static func compose(_ error: SkimComposeError) -> String {
        switch error {
        case .refused, .guardrailViolation: refused
        case .contextSizeExceeded: tooLong
        case .generationFailed, .noOutput: generic
        }
    }
}

/// Where a Skim run stands. A run only ever shows a whole page or a failure;
/// never a half-built one.
enum SkimRunState: Equatable {
    case idle
    case working(SkimProgress)
    case finished(SkimPage)
    case failed(SkimFailure)
}

/// The pieces a run is made of; fakes slot in for tests.
struct SkimDependencies: Sendable {
    var finder: any ResultFinding
    var reader: any PageReading
    var composer: any SkimComposing

    static var live: SkimDependencies {
        SkimDependencies(finder: ResultFinder(), reader: PageReader(), composer: SkimComposer())
    }
}

/// One Skim from start to finish: find the results, read the sources, compose
/// the page — and, on "Dig deeper", read on up to ten and compose again.
@MainActor
@Observable
final class SkimRun {

    private(set) var state: SkimRunState = .idle

    let query: String
    let engine: SearchEngine

    private let dependencies: SkimDependencies
    private var task: Task<Void, Never>?

    /// The result links found, kept so "Dig deeper" can read on through them.
    private var links: [URL] = []
    /// The sources read so far, in result order.
    private var readPages: [ReadPage] = []
    /// How many pages were asked for, read or not.
    private var attempted = 0

    init(query: String, engine: SearchEngine, dependencies: SkimDependencies = .live) {
        self.query = query
        self.engine = engine
        self.dependencies = dependencies
    }

    var page: SkimPage? {
        if case .finished(let page) = state { return page }
        return nil
    }

    var failure: SkimFailure? {
        if case .failed(let failure) = state { return failure }
        return nil
    }

    // MARK: Running

    /// Starts over: find the results, read the first three, compose.
    func start() {
        task?.cancel()
        links = []
        readPages = []
        attempted = 0
        state = .working(SkimProgress())
        task = Task { [weak self] in
            await self?.run()
        }
    }

    /// The working screen's Cancel. The run stops where it is.
    func cancel() {
        task?.cancel()
    }

    private func run() async {
        let found = await dependencies.finder.topResultLinks(query: query, engine: engine)
        guard !Task.isCancelled else { return }
        guard let found, !found.isEmpty else {
            state = .failed(SkimFailure(line: SkimFailureLines.engineDown))
            return
        }
        links = found
        await readInitialAndCompose()
    }

    private func readInitialAndCompose() async {
        let first = Array(links.prefix(SkimPage.initialSourceCount))
        state = .working(SkimProgress(plannedHosts: first.map(hosts), plannedCount: first.count))
        let pages = await read(first)
        guard !Task.isCancelled else { return }
        await compose(pages)
    }

    /// Reads sources past the first three, up to ten in all, and composes again.
    /// The page that already exists stands if the deeper one cannot be built.
    func digDeeper() {
        guard let current = page, current.canDigDeeper else { return }
        task?.cancel()
        let target = min(SkimPage.maxSources, links.count)
        let next = Array(links.prefix(target).dropFirst(readPages.count))
        guard !next.isEmpty else { return }
        state = .working(
            SkimProgress(
                plannedHosts: links.prefix(target).map(hosts),
                readCount: readPages.count,
                plannedCount: target))
        task = Task { [weak self] in
            await self?.readMoreAndCompose(current: current, next: next)
        }
    }

    private func readMoreAndCompose(current: SkimPage, next: [URL]) async {
        let more = await read(next)
        guard !Task.isCancelled else { return }
        let all = readPages + more
        do {
            let page = try await dependencies.composer.compose(query: query, sources: all)
            guard !Task.isCancelled else { return }
            readPages = all
            state = .finished(page)
        } catch {
            guard !Task.isCancelled else { return }
            state = .finished(current)
        }
    }

    // MARK: Reading

    /// Reads pages three at a time, in order, filling in the run's progress as
    /// each one lands or fails.
    private func read(_ urls: [URL]) async -> [ReadPage] {
        let reader = dependencies.reader
        var pages: [ReadPage] = []
        var index = 0
        while index < urls.count, !Task.isCancelled {
            let wave = Array(urls[index..<min(index + SkimPage.initialSourceCount, urls.count)])
            index += wave.count
            let read: [ReadPage?] = await withTaskGroup(of: (Int, ReadPage?).self) { group in
                for (offset, url) in wave.enumerated() {
                    group.addTask {
                        await (offset, reader.read(url))
                    }
                }
                var out = [ReadPage?](repeating: nil, count: wave.count)
                for await (offset, page) in group {
                    out[offset] = page
                    markRead(page)
                }
                return out
            }
            pages.append(contentsOf: read.compactMap(\.self))
        }
        return pages
    }

    private func markRead(_ page: ReadPage?) {
        guard case .working(var progress) = state else { return }
        attempted += 1
        if page != nil { progress.readCount += 1 }
        state = .working(progress)
    }

    // MARK: Composing

    private func compose(_ pages: [ReadPage]) async {
        guard pages.count >= 2 else {
            state = .failed(
                SkimFailure(line: SkimFailureLines.tooFew(read: pages.count, attempted: attempted)))
            return
        }
        readPages = pages
        do {
            let page = try await dependencies.composer.compose(query: query, sources: pages)
            guard !Task.isCancelled else { return }
            state = .finished(page)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(SkimFailure(line: SkimFailureLines.compose(SkimComposeError.classify(error))))
        }
    }

    private func hosts(_ url: URL) -> String {
        HostFormatter.host(for: url)
    }

    /// Lands on a state the run did not run into: a saved page brought back by
    /// its bookmark, or a fixed state for the UI tests.
    func land(_ newState: SkimRunState) {
        task?.cancel()
        if case .finished(let page) = newState {
            links = page.sources.map(\.url)
            readPages = []
        }
        state = newState
    }
}
