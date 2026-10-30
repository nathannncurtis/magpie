import Testing

@testable import Magpie

@Suite("ChromeCollapse")
struct ReadingChromeTests {

    @Test("the first scroll position only sets the baseline")
    func baseline() {
        var chrome = ChromeCollapse()
        #expect(chrome.scrollDidChange(offsetY: 0, atEndOfPage: false) == .unchanged)
        #expect(chrome.progress == 0)
        #expect(chrome.lastOffset == 0)
    }

    @Test("a page too short to scroll never collapses")
    func unscrollable() {
        var chrome = ChromeCollapse()
        #expect(chrome.scrollDidChange(offsetY: 0, atEndOfPage: true) == .unchanged)
        #expect(chrome.scrollDidChange(offsetY: 0, atEndOfPage: true) == .unchanged)
        #expect(chrome.progress == 0)
    }

    @Test("24 points of downward scroll slims the bar")
    func thresholdSlims() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        #expect(chrome.scrollDidChange(offsetY: 24, atEndOfPage: false) == .settle)
        #expect(chrome.progress == 1)
    }

    @Test("the collapse tracks the scroll, then settles")
    func tracking() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        #expect(chrome.scrollDidChange(offsetY: 12, atEndOfPage: false) == .track)
        #expect(chrome.progress == 0.5)
        #expect(chrome.scrollDidChange(offsetY: 18, atEndOfPage: false) == .track)
        #expect(chrome.progress == 0.75)
        #expect(chrome.scrollDidChange(offsetY: 42, atEndOfPage: false) == .settle)
        #expect(chrome.progress == 1)
    }

    @Test("scrolling past the threshold keeps the bar slim")
    func pastThreshold() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        _ = chrome.scrollDidChange(offsetY: 24, atEndOfPage: false)
        #expect(chrome.scrollDidChange(offsetY: 200, atEndOfPage: false) == .unchanged)
        #expect(chrome.progress == 1)
    }

    @Test("standing still changes nothing")
    func still() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 30, atEndOfPage: false)
        #expect(chrome.scrollDidChange(offsetY: 30, atEndOfPage: false) == .unchanged)
    }

    @Test("any upward scroll brings the full bar back")
    func upwardExpands() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        _ = chrome.scrollDidChange(offsetY: 24, atEndOfPage: false)
        #expect(chrome.scrollDidChange(offsetY: 20, atEndOfPage: false) == .settle)
        #expect(chrome.progress == 0)
    }

    @Test("upward scroll also undoes a partial collapse")
    func upwardUndoesPartial() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        _ = chrome.scrollDidChange(offsetY: 12, atEndOfPage: false)
        #expect(chrome.scrollDidChange(offsetY: 8, atEndOfPage: false) == .settle)
        #expect(chrome.progress == 0)
    }

    @Test("the end of the page brings the full bar back")
    func endOfPage() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        _ = chrome.scrollDidChange(offsetY: 24, atEndOfPage: false)
        #expect(chrome.scrollDidChange(offsetY: 400, atEndOfPage: true) == .settle)
        #expect(chrome.progress == 0)
    }

    @Test("a pause below the threshold snaps back to the full bar")
    func snap() {
        var chrome = ChromeCollapse()
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        _ = chrome.scrollDidChange(offsetY: 12, atEndOfPage: false)
        #expect(chrome.snap() == .settle)
        #expect(chrome.progress == 0)
    }

    @Test("snap leaves a settled bar alone")
    func snapSettled() {
        var chrome = ChromeCollapse()
        _ = chrome.snap()
        #expect(chrome.progress == 0)
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        _ = chrome.scrollDidChange(offsetY: 24, atEndOfPage: false)
        #expect(chrome.snap() == .unchanged)
        #expect(chrome.progress == 1)
    }

    @Test("expand brings the slim pill back to the full bar")
    func expand() {
        var chrome = ChromeCollapse()
        #expect(chrome.expand() == .unchanged)
        _ = chrome.scrollDidChange(offsetY: 0, atEndOfPage: false)
        _ = chrome.scrollDidChange(offsetY: 24, atEndOfPage: false)
        #expect(chrome.expand() == .settle)
        #expect(chrome.progress == 0)
    }
}
