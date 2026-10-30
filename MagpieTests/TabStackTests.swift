import CoreGraphics
import Testing

@testable import Magpie

@Suite("Fling to close")
struct TabStackTests {

    private let cardHeight: CGFloat = 1000

    @Test("closes past 30% of the card height")
    func distanceThreshold() {
        #expect(FlingToClose.closes(translationY: -301, velocityY: 0, cardHeight: cardHeight))
        #expect(!FlingToClose.closes(translationY: -299, velocityY: 0, cardHeight: cardHeight))
        #expect(!FlingToClose.closes(translationY: -300, velocityY: 0, cardHeight: cardHeight))
    }

    @Test("closes faster than 500 pt/s")
    func velocityThreshold() {
        #expect(FlingToClose.closes(translationY: 0, velocityY: -501, cardHeight: cardHeight))
        #expect(!FlingToClose.closes(translationY: 0, velocityY: -499, cardHeight: cardHeight))
        #expect(!FlingToClose.closes(translationY: 0, velocityY: -500, cardHeight: cardHeight))
    }

    @Test("downward movement never closes")
    func downwardNeverCloses() {
        #expect(!FlingToClose.closes(translationY: 400, velocityY: 900, cardHeight: cardHeight))
        #expect(!FlingToClose.closes(translationY: -100, velocityY: 600, cardHeight: cardHeight))
    }
}
