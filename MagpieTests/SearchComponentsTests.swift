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

    @Test("the mark fills its design space without spilling it")
    func markGeometry() {
        let bounds = MarkGeometry.drawnBounds
        #expect(bounds.minX >= 0 && bounds.maxX <= MarkGeometry.units)
        #expect(bounds.minY >= 0 && bounds.maxY <= MarkGeometry.units)
        #expect(bounds.width > MarkGeometry.units / 2)
        #expect(bounds.height > MarkGeometry.units / 2)
        // The bead sits inside the sweep's arms, not over its ends.
        let beadTop = MarkGeometry.beadCenter.y - MarkGeometry.beadRadius
        #expect(beadTop > bounds.minY + MarkGeometry.strokeWidth)
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
