import CoreGraphics
import Testing

@testable import Magpie

@Suite("Search components")
struct SearchComponentsTests {

    @Test("the Skim pill hides entirely when Skim is off or unavailable")
    func skimPillHides() {
        #expect(SkimPill.State.resolve(skimEnabled: false, primed: true) == .hidden)
        #expect(SkimPill.State.resolve(skimEnabled: false, primed: false) == .hidden)
    }

    @Test("only the first row is primed")
    func skimPillPriming() {
        #expect(SkimPill.State.resolve(skimEnabled: true, primed: true) == .primed)
        #expect(SkimPill.State.resolve(skimEnabled: true, primed: false) == .resting)
    }

    @Test("the artwork traced from the asset is whole")
    func markArtwork() {
        #expect(MarkPath.brush.count == 11)
        #expect(MarkPath.brush.allSatisfy { !$0.isEmpty })
        // The dry gap and the bead lie inside the artwork's square.
        let gap = MarkPath.dryGapCenter
        let bead = MarkPath.beadCenter
        #expect(gap.x > 0 && gap.x < MarkPath.units && gap.y > 0 && gap.y < MarkPath.units)
        #expect(bead.x > 0 && bead.x < MarkPath.units && bead.y > 0 && bead.y < MarkPath.units)
    }

    @Test("the mark fills its design space without spilling it")
    func markGeometry() {
        let bounds = MarkGeometry.drawnBounds
        #expect(bounds.minX >= 0 && bounds.maxX <= MarkPath.units)
        #expect(bounds.minY >= 0 && bounds.maxY <= MarkPath.units)
        #expect(bounds.width > MarkPath.units / 2)
        #expect(bounds.height > MarkPath.units / 2)
        // Fitting the mark keeps its aspect and centres it.
        let square = CGRect(x: 0, y: 0, width: 100, height: 100)
        let fitted = MarkPath.brushPath().applying(MarkGeometry.transform(into: square))
            .boundingRect
        #expect(abs(fitted.midX - square.midX) < 1)
        #expect(abs(fitted.midY - square.midY) < 1)
    }

    @Test("the reveal centreline lives in the artwork's space")
    func markCentreline() {
        let bounds = MarkGeometry.centreline().boundingRect
        #expect(bounds.minX >= 0 && bounds.maxX <= MarkPath.units)
        #expect(bounds.minY >= 0 && bounds.maxY <= MarkPath.units)
    }

    @Test("the stub provider filters by prefix and honours the enabled flag")
    func stubProvider() async {
        let stub = StubSuggestionProvider(
            rowsByPrefix: ["seasoning carbon steel", "seasoning cast iron", "carbon steel vs cast iron"])
        #expect(
            await stub.suggestions(for: "seasoning", engine: .default, enabled: true)
                == ["seasoning carbon steel", "seasoning cast iron"])
        #expect(await stub.suggestions(for: "zzz", engine: .default, enabled: true) == [])
        #expect(await stub.suggestions(for: "seasoning", engine: .default, enabled: false) == [])
        #expect(await stub.suggestions(for: "", engine: .default, enabled: true) == [])
    }
}
