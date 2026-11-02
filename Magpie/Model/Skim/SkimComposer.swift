import Foundation
import FoundationModels

/// Why a page could not be composed.
enum SkimComposeError: Error, Equatable {
    case refused
    case guardrailViolation
    case contextSizeExceeded
    case generationFailed
    case noOutput

    /// Reads the reason off a thrown error by its case name. The framework
    /// renamed its error cases across releases; naming either spelling trips
    /// deprecation warnings, so match the names instead.
    static func classify(_ error: Error) -> SkimComposeError {
        switch caseName(of: error) {
        case "refusal": .refused
        case "guardrailViolation": .guardrailViolation
        case "contextSizeExceeded", "exceededContextWindowSize": .contextSizeExceeded
        default: .generationFailed
        }
    }
}

private func caseName(of error: Error) -> String? {
    let mirror = Mirror(reflecting: error)
    if mirror.displayStyle == .enum, let label = mirror.children.first?.label {
        return label
    }
    return String(describing: error)
}

@Generable(description: "A short sourced page that answers a search query")
struct GeneratedSkimPage {
    @Guide(description: "The page title: two to six plain words, no quotes, no colon")
    var title: String

    @Guide(description: "The page's points; four to seven of them", .count(4...7))
    var sections: [GeneratedSkimSection]
}

@Generable(description: "One point of the page")
struct GeneratedSkimSection {
    @Guide(description: "One emoji that fits the point")
    var emoji: String

    @Guide(description: "A short bold term naming the point: one to three words")
    var term: String

    @Guide(description: "One plain sentence stating the point, under twenty-five words")
    var claim: String

    @Guide(description: "The 1-based numbers of the sources that back the point, at least one", .count(1...8))
    var citations: [Int]
}

/// What a Skim run uses to turn read sources into a finished page.
protocol SkimComposing: Sendable {
    func compose(query: String, sources: [ReadPage]) async throws -> SkimPage
}

/// Composes a Skim page with the on-device model. Sources that together do not
/// fit are summarized first, one session each, then the page is composed from
/// the summaries.
struct SkimComposer: SkimComposing {

    var instructions: String = """
        You build Skim pages: short, sourced briefs that answer a search query.
        Plain, terse voice. Short sentences; no exclamation marks; no hype.
        Write in the query's language.
        Use only what the sources say; never invent facts, numbers, or names.
        Every point must cite at least one source number.
        """

    var summaryInstructions: String = """
        You condense one web page into plain notes for a brief.
        Keep the facts, numbers, and names; drop everything else.
        No headings, no commentary, no exclamation marks.
        """

    /// Tokens kept back for the instructions, the schema, and the page itself.
    private var reservedTokens = 1_200
    /// Rough characters per token, for sizing prompts.
    private var charactersPerToken = 4

    func compose(query: String, sources: [ReadPage]) async throws -> SkimPage {
        let texts = try await fittedTexts(query: query, sources: sources)

        var prompt = "Query: \(query)\n"
        for (index, source) in sources.enumerated() {
            prompt += "\n[\(index + 1)] \(source.host) — \(source.title)\n\(texts[index])\n"
        }
        prompt += "\nWrite the Skim page for the query from these sources."

        let session = LanguageModelSession(instructions: instructions)
        let generated = try await session.respond(to: prompt, generating: GeneratedSkimPage.self).content

        let sections = ComposerPolish.sections(from: generated.sections, sourceCount: sources.count)
        let title = ComposerPolish.title(from: generated.title, fallback: query)
        guard !sections.isEmpty else { throw SkimComposeError.noOutput }
        return SkimPage(query: query, title: title, sections: sections, sources: sources.map(Self.reference))
    }

    private static func reference(_ page: ReadPage) -> SkimSourceRef {
        SkimSourceRef(
            url: page.url,
            title: page.title,
            host: page.host,
            faviconURL: page.faviconURL,
            imageURL: page.imageURL)
    }

    /// The text to compose from: each source as-is when they all fit, otherwise
    /// each source summarized into its share of the window.
    private func fittedTexts(query: String, sources: [ReadPage]) async throws -> [String] {
        let budget =
            max(
                0, SystemLanguageModel.default.contextSize - reservedTokens) * charactersPerToken
        let total = sources.reduce(0) { $0 + $1.text.count }
        guard total > budget else { return sources.map(\.text) }

        let perSource = max(800, budget / sources.count)
        var out: [String] = []
        for source in sources {
            let session = LanguageModelSession(instructions: summaryInstructions)
            let prompt = "Query: \(query)\nPage: \(source.title) (\(source.host))\n\n\(source.text)"
            let summary = try await session.respond(to: prompt).content
            out.append(String(summary.prefix(perSource)))
        }
        return out
    }
}

/// Post-processing of a composed page: only points that cite real sources
/// survive. Pure, so it is tested directly.
enum ComposerPolish {

    static let maxSections = 7

    static func sections(from generated: [GeneratedSkimSection], sourceCount: Int) -> [SkimSection] {
        var seenTerms = Set<String>()
        var out: [SkimSection] = []
        for point in generated {
            let term = point.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let claim = point.claim.trimmingCharacters(in: .whitespacesAndNewlines)
            let emoji = point.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !claim.isEmpty else { continue }

            var citations: [Int] = []
            for citation in point.citations {
                let clamped = min(max(citation, 1), sourceCount)
                guard !citations.contains(clamped) else { continue }
                citations.append(clamped)
            }
            guard !citations.isEmpty else { continue }

            let key = term.lowercased()
            guard !seenTerms.contains(key) else { continue }
            seenTerms.insert(key)

            out.append(SkimSection(emoji: emoji, term: term, claim: claim, citations: citations))
            if out.count == maxSections { break }
        }
        return out
    }

    static func title(from title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(60))
    }
}
