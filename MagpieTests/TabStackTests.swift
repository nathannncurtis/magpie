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

@Suite("Stack layout")
struct StackLayoutTests {

    /// A phone-shaped container, in points.
    private let container = CGSize(width: 402, height: 874)

    private var cardWidth: CGFloat { container.width * 0.62 }
    private var stride: CGFloat { cardWidth + 14 }

    @Test("the current card is centred at 62% of the container")
    func currentCardCentred() {
        let frame = StackLayout.cardFrame(offset: 0, container: container)

        #expect(frame.width == cardWidth)
        #expect(frame.height == container.height * 0.62)
        #expect(frame.midX == container.width / 2)
        #expect(frame.midY == container.height / 2)
    }

    @Test("neighbours peek in from both edges by the same amount")
    func neighboursPeekSymmetrically() {
        let left = StackLayout.cardFrame(offset: -1, container: container)
        let right = StackLayout.cardFrame(offset: 1, container: container)

        let leftPeek = left.maxX
        let rightPeek = container.width - right.minX
        #expect(leftPeek > 0)
        #expect(rightPeek > 0)
        #expect(abs(leftPeek - rightPeek) < 0.001)
        #expect(left.maxX == stride - cardWidth / 2)
        #expect(right.minX == container.width / 2 + stride - cardWidth / 2)
    }

    @Test("a drag shifts every card with it")
    func dragShiftsTheRow() {
        let frame = StackLayout.cardFrame(offset: 0, container: container, drag: -40)

        #expect(frame.midX == container.width / 2 - 40)
    }

    @Test("a label leads its card and stops short of the next one")
    func labelLeadsItsCard() {
        let card = StackLayout.cardFrame(offset: 0, container: container)
        let nextLeading = StackLayout.cardFrame(offset: 1, container: container).minX
        let window = StackLayout.labelWindow(card: card, nextCardLeading: nextLeading, containerWidth: container.width)

        #expect(window.minX == card.minX + 6)
        #expect(window.maxX == min(card.maxX, nextLeading - 6, container.width - 16))
        #expect(window.maxY == card.minY - 12)
        #expect(window.height == 22)
    }

    @Test("a peeking label clamps to the screen edge with its card")
    func peekingLabelClamps() {
        let card = StackLayout.cardFrame(offset: -1, container: container)
        let nextLeading = StackLayout.cardFrame(offset: 0, container: container).minX
        let window = StackLayout.labelWindow(card: card, nextCardLeading: nextLeading, containerWidth: container.width)

        #expect(window.minX == 14)
        #expect(window.maxX == min(card.maxX, nextLeading - 6))
    }
}
