import Testing

@testable import Magpie

@Suite("Springs")
struct SpringTests {

    @Test("the named springs match the motion table")
    func springsMatchTable() {
        #expect(Springs.chrome == Springs.Spring(response: 0.3, dampingFraction: 0.88))
        #expect(Springs.settle == Springs.Spring(response: 0.28, dampingFraction: 0.9))
        #expect(Springs.snap == Springs.Spring(response: 0.34, dampingFraction: 0.72))
        #expect(Springs.smoothDuration == 0.35)
    }
}
