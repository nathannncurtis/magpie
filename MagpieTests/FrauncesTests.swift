import CoreText
import Testing
import UIKit

@testable import Magpie

@Suite("Fraunces")
struct FrauncesTests {

    @Test("the bundled font registers and loads by family name")
    func bundledFontLoads() throws {
        let font = try #require(UIFont(name: FrauncesFace.familyName, size: 46))
        let descriptor = font.fontDescriptor as CTFontDescriptor
        let url = try #require(CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL)
        #expect(url.lastPathComponent == "Fraunces[SOFT,WONK,opsz,wght].ttf")
    }

    @Test("the display font pins the weight, softness and wonk axes")
    func displayAxes() throws {
        let variations = try #require(CTFontCopyVariation(FrauncesFace.ctFont(46)) as? [AnyHashable: Any])
        let wght: FourCharCode = 0x7767_6874
        let soft: FourCharCode = 0x534F_4654
        let wonk: FourCharCode = 0x574F_4E4B
        #expect(axisValue(wght, variations) == FrauncesFace.weight)
        #expect(axisValue(soft, variations) == FrauncesFace.softness)
        #expect(axisValue(wonk, variations) == FrauncesFace.wonk)
    }

    @Test("the optical size axis follows the point size")
    func opticalSizeFollowsSize() throws {
        let variations = try #require(CTFontCopyVariation(FrauncesFace.ctFont(46)) as? [AnyHashable: Any])
        let opsz: FourCharCode = 0x6F70_737A
        #expect(axisValue(opsz, variations) == 46)
    }
}

/// The value a variation dictionary holds for one axis tag.
private func axisValue(_ tag: FourCharCode, _ variations: [AnyHashable: Any]) -> Double? {
    for (key, value) in variations {
        if let keyNumber = key as? NSNumber, keyNumber.uint32Value == tag {
            return (value as? NSNumber)?.doubleValue
        }
    }
    return nil
}
