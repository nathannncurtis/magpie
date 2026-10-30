import Foundation
import Testing

@testable import Magpie

/// The composed page's post-processing: only points that cite a real source
/// survive, and the failure reasons read off thrown errors.
@Suite("SkimComposer")
struct SkimComposerTests {

    private func point(
        emoji: String = "🔥", term: String, claim: String = "A plain sentence.",
        citations: [Int]
    ) -> GeneratedSkimSection {
        GeneratedSkimSection(emoji: emoji, term: term, claim: claim, citations: citations)
    }

    // MARK: Sections

    @Test("sound points survive in their order")
    func soundPointsSurvive() {
        let sections = ComposerPolish.sections(
            from: [
                point(term: "Method", citations: [1, 3]),
                point(term: "Oil", citations: [2]),
            ], sourceCount: 3)

        #expect(sections.map(\.term) == ["Method", "Oil"])
        #expect(sections[0].citations == [1, 3])
    }

    @Test("points with no real citation are dropped")
    func uncitedPointsDrop() {
        let sections = ComposerPolish.sections(
            from: [
                point(term: "Method", citations: []),
                point(term: "Oil", citations: [1]),
                point(term: "Nothing", citations: [0]),
            ], sourceCount: 2)

        // A citation of zero is pulled up to the first source, not dropped;
        // an empty citation list takes the point with it.
        #expect(sections.map(\.term) == ["Oil", "Nothing"])
        #expect(sections[1].citations == [1])
    }

    @Test("citations past the sources pull back into range, once each")
    func citationsClamp() {
        let sections = ComposerPolish.sections(
            from: [point(term: "Method", citations: [5, 2, 2, 9, 1])], sourceCount: 3)

        #expect(sections[0].citations == [3, 2, 1])
    }

    @Test("empty or repeated points are dropped")
    func emptyAndRepeatedDrop() {
        let sections = ComposerPolish.sections(
            from: [
                point(term: "  ", citations: [1]),
                point(term: "Method", claim: "   ", citations: [1]),
                point(term: "Method", citations: [1]),
                point(term: "method", citations: [2]),
                point(term: "Oil", citations: [1]),
            ], sourceCount: 2)

        #expect(sections.map(\.term) == ["Method", "Oil"])
    }

    @Test("at most seven points stand")
    func cappedAtSeven() {
        let generated = (1...9).map { point(term: "Point\($0)", citations: [1]) }
        let sections = ComposerPolish.sections(from: generated, sourceCount: 2)

        #expect(sections.count == 7)
        #expect(sections.map(\.term) == (1...7).map { "Point\($0)" })
    }

    // MARK: Title

    @Test("a title stands trimmed, capped at sixty characters")
    func titlesTrim() {
        let sixty = String(repeating: "t", count: 80)

        #expect(ComposerPolish.title(from: "  Seasoning  ", fallback: "query") == "Seasoning")
        #expect(ComposerPolish.title(from: sixty, fallback: "query").count == 60)
        #expect(ComposerPolish.title(from: "  ", fallback: "query") == "query")
    }

    // MARK: Errors

    @Test("thrown errors read by their case name")
    func errorsClassify() {
        #expect(SkimComposeError.classify(StubError.refusal) == .refused)
        #expect(SkimComposeError.classify(StubError.guardrailViolation) == .guardrailViolation)
        #expect(SkimComposeError.classify(StubError.contextSizeExceeded) == .contextSizeExceeded)
        #expect(SkimComposeError.classify(StubError.exceededContextWindowSize) == .contextSizeExceeded)
        #expect(SkimComposeError.classify(StubError.networkFailure) == .generationFailed)
        #expect(SkimComposeError.classify(StubError.simple) == .generationFailed)
    }

    @Test("each failure line is a line, in the app's voice")
    func failureLines() {
        #expect(SkimFailureLines.tooFew(read: 1, attempted: 3).hasSuffix("That's not enough to Skim."))
        #expect(!SkimFailureLines.refused.isEmpty)
        #expect(!SkimFailureLines.compose(.guardrailViolation).isEmpty)
    }
}

/// The thrown shapes the framework's errors take, without naming its enums.
private enum StubError: Error {
    case refusal
    case guardrailViolation
    case contextSizeExceeded
    case exceededContextWindowSize
    case networkFailure
    case simple
}
