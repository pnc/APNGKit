import Foundation
import XCTest
@testable import APNGKit

class PaletteTests: XCTestCase {
  func medianCut(_ named: String, colors: UInt) -> ManhattanDistancePalette<RGBASample> {
    let image = UIImage(named: named,
      in: Bundle.testBundle, compatibleWith: nil)!
    let builder = MedianCutPaletteBuilder<ManhattanDistancePalette<RGBASample>>(colors: colors)
    try! builder.addImage(image.cgImage!)
    return builder.toPalette()
  }

  func testFindsOpaqueColors() {
    let findOpaque = { (image: String) -> [RGBASample] in
      let opaque = self.medianCut(image, colors: 256).colors.filter { (sample) -> Bool in
        return sample[.A] == 255
      }
      return opaque
    }

    let reds = findOpaque("1")
    XCTAssert(reds.contains(RGBASample(r: 211, g: 0, b: 0, a: 255)),
              "Unable to find red = 211 opaque sample: \(reds)")

    let greens = findOpaque("2")
    XCTAssert(greens.contains(RGBASample(r: 0, g: 128, b: 0, a: 255)),
              "Unable to find green = 128 opaque sample: \(greens)")

    let blues = findOpaque("3")
    XCTAssert(blues.contains(RGBASample(r: 0, g: 0, b: 255, a: 255)),
              "Unable to find blue = 211 opaque sample: \(blues)")
  }

  func testFindsRelevantColors() {
    let palette = medianCut("gradient_rgb", colors: 4)
    let red = RGBASample(r: 255, g: 0, b: 0, a: 255)
    let green = RGBASample(r: 0, g: 255, b: 0, a: 255)
    let blue = RGBASample(r: 0, g: 0, b: 255, a: 255)
    let gray = RGBASample(r: 128, g: 128, b: 128, a: 255)
    XCTAssertEqual(Set([red, green, blue, gray]),
                   Set(palette.colors))
  }

  func testConvertsImage() {
    let image = UIImage(named: "bug",
      in: Bundle.testBundle, compatibleWith: nil)!.cgImage!
    let outImage = self.medianCut("bug", colors: 256).convert(image: image)
    //let uiImage = UIImage(cgImage: outImage)
    XCTAssert(outImage.colorSpace!.model == .indexed,
              "Wrong CGColorSpaceModel: \(outImage.colorSpace!.model.rawValue)")
    XCTAssertEqual(4, outImage.colorSpace!.colorTable!.count)
  }
}
