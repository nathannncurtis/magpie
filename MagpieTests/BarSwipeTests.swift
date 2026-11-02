import CoreGraphics
import Testing

@testable import Magpie

@Suite("Bar swipe")
struct BarSwipeTests {

    @Test("no axis locks before 24 pt of travel")
    func lockNeedsTravel() {
        #expect(BarSwipe.axis(for: CGSize(width: 23, height: -5)) == nil)
        #expect(BarSwipe.axis(for: CGSize(width: -30, height: 4)) == .horizontal)
        #expect(BarSwipe.axis(for: CGSize(width: 6, height: -30)) == .up)
    }

    @Test("a downward drag locks nothing")
    func downIsIgnored() {
        #expect(BarSwipe.axis(for: CGSize(width: 3, height: 40)) == nil)
    }

    @Test("a left drag steps to the next tab, a right drag to the previous")
    func directions() {
        let left = BarSwipe.step(
            translation: -120, predicted: -160, width: 390, hasPrevious: true, hasNext: true)
        let right = BarSwipe.step(
            translation: 120, predicted: 160, width: 390, hasPrevious: true, hasNext: true)
        #expect(left == 1)
        #expect(right == -1)
    }

    @Test("a short, slow drag steps nowhere; a flick does")
    func threshold() {
        #expect(
            BarSwipe.step(translation: -40, predicted: -60, width: 390, hasPrevious: true, hasNext: true)
                == 0)
        #expect(
            BarSwipe.step(translation: -40, predicted: -300, width: 390, hasPrevious: true, hasNext: true)
                == 1)
    }

    @Test("nothing steps past an end of the stack")
    func ends() {
        #expect(
            BarSwipe.step(translation: -200, predicted: -200, width: 390, hasPrevious: true, hasNext: false)
                == 0)
        #expect(
            BarSwipe.step(translation: 200, predicted: 200, width: 390, hasPrevious: false, hasNext: true)
                == 0)
    }

    @Test("past an end the page rubber-bands short of its limit")
    func rubberBand() {
        let free = BarSwipe.offset(translation: -150, hasPrevious: true, hasNext: true)
        let banded = BarSwipe.offset(translation: -150, hasPrevious: true, hasNext: false)
        #expect(free == -150)
        #expect(banded < 0 && banded > -BarSwipe.rubberLimit)
    }

    @Test("swipe up opens the stack by distance or by flick")
    func upThreshold() {
        #expect(BarSwipe.opensStack(translationY: -60, predictedY: -60))
        #expect(BarSwipe.opensStack(translationY: -30, predictedY: -200))
        #expect(!BarSwipe.opensStack(translationY: -30, predictedY: -60))
    }
}

@Suite("Stack swipe step")
struct StackSwipeStepTests {

    private func step(_ translation: CGFloat, _ predicted: CGFloat, current: Int = 2, count: Int = 5)
        -> Int
    {
        StackLayout.swipeStep(
            translation: translation, predicted: predicted, stride: 100, current: current, count: count)
    }

    @Test("a quarter-stride drag moves one tab")
    func oneTab() {
        #expect(step(-30, -30) == 1)
        #expect(step(30, 30) == -1)
        #expect(step(-20, -20) == 0)
    }

    @Test("the step grows with the predicted end")
    func proportional() {
        #expect(step(-60, -150) == 2)
        #expect(step(60, 250, current: 4, count: 6) == -2)
    }

    @Test("the step is clamped to the stack")
    func clamped() {
        #expect(step(-60, -900) == 2)
        #expect(step(60, 900) == -2)
        #expect(step(-60, -900, current: 4) == 0)
    }
}
