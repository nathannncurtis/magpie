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

    /// CGRect positions add widths onto origins, so derived edges can round a ulp.
    private func approximately(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) < 0.001
    }

    @Test("the current card is centered at 62% of the container")
    func currentCardCentred() {
        let frame = StackLayout.cardFrame(offset: 0, container: container)

        #expect(approximately(frame.width, cardWidth))
        #expect(approximately(frame.height, container.height * 0.62))
        #expect(approximately(frame.midX, container.width / 2))
        #expect(approximately(frame.midY, container.height / 2))
    }

    @Test("neighbors peek in from both edges by the same amount")
    func neighborsPeekSymmetrically() {
        let left = StackLayout.cardFrame(offset: -1, container: container)
        let right = StackLayout.cardFrame(offset: 1, container: container)

        let leftPeek = left.maxX
        let rightPeek = container.width - right.minX
        #expect(leftPeek > 0)
        #expect(rightPeek > 0)
        #expect(approximately(leftPeek, rightPeek))
        #expect(approximately(leftPeek, container.width / 2 - stride + cardWidth / 2))
        #expect(approximately(right.minX, container.width / 2 + stride - cardWidth / 2))
    }

    @Test("a drag shifts every card with it")
    func dragShiftsTheRow() {
        let frame = StackLayout.cardFrame(offset: 0, container: container, drag: -40)

        #expect(approximately(frame.midX, container.width / 2 - 40))
    }

    @Test("a label leads its card and stops short of the next one")
    func labelLeadsItsCard() {
        let card = StackLayout.cardFrame(offset: 0, container: container)
        let nextLeading = StackLayout.cardFrame(offset: 1, container: container).minX
        let window = StackLayout.labelWindow(card: card, nextCardLeading: nextLeading, containerWidth: container.width)

        #expect(approximately(window.minX, card.minX + 6))
        #expect(approximately(window.maxX, min(card.maxX, nextLeading - 6, container.width - 16)))
        #expect(approximately(window.maxY, card.minY - 12))
        #expect(window.height == 22)
    }

    @Test("a peeking label clamps to the screen edge with its card")
    func peekingLabelClamps() {
        let card = StackLayout.cardFrame(offset: -1, container: container)
        let nextLeading = StackLayout.cardFrame(offset: 0, container: container).minX
        let window = StackLayout.labelWindow(card: card, nextCardLeading: nextLeading, containerWidth: container.width)

        #expect(approximately(window.minX, 14))
        #expect(approximately(window.maxX, min(card.maxX, nextLeading - 6)))
    }

    @Test("a card and its label lift by the flight, else the drag, else not at all")
    func liftFollowsTheCard() {
        #expect(StackLayout.lift(for: 1, flying: 1, flyOffset: -900, dragging: nil, drag: 0) == -900)
        #expect(StackLayout.lift(for: 1, flying: nil, flyOffset: 0, dragging: 1, drag: -120) == -120)
        #expect(StackLayout.lift(for: 2, flying: 1, flyOffset: -900, dragging: 1, drag: -120) == 0)
    }
}
