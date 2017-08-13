import Foundation
import UIKit

public protocol Palette {
  associatedtype SampleType: Sample
  init(_ colors: [SampleType])
  var colors: [SampleType] { get }
  func convert(image: CGImage) -> CGImage
}

public protocol PaletteBuilder {
  associatedtype SampleType
  associatedtype PaletteType
  func addImage(_ image: CGImage) throws
  func toPalette() -> PaletteType
}

public protocol Sample: Hashable, Equatable {
  associatedtype ComponentType: Hashable
  static var componentTypes: [ComponentType] { get }
  //var components: [ComponentType] { get }
  init(_ components: [UInt8])
  subscript(component: ComponentType) -> UInt8 { get }
}

public enum RGBA {
  case R; case G; case B; case A
}

public struct RGBASample: Hashable, Equatable, Sample {
  public static var componentTypes = [RGBA.R, .G, .B, .A]

  var r: UInt8
  var g: UInt8
  var b: UInt8
  var a: UInt8

  public init(_ components: [UInt8]) {
    // Assuming BGRA
    self.init(r: components[2], g: components[1], b: components[0], a: components[3])
  }

  public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }

  public static func ==(lhs: RGBASample, rhs: RGBASample) -> Bool {
    return lhs.r == rhs.r &&
      lhs.g == rhs.g &&
      lhs.b == rhs.b &&
      lhs.a == rhs.a
  }

  public var hashValue: Int {
    return r.hashValue ^ g.hashValue ^ b.hashValue ^ a.hashValue
  }

  public typealias SampleType = RGBA
  public subscript(component: RGBA) -> UInt8 {
    get {
      switch component {
      case .R: return r
      case .G: return g
      case .B: return b
      case .A: return a
      }
    }

    mutating set {
      switch component {
      case .R: r = newValue
      case .G: g = newValue
      case .B: b = newValue
      case .A: a = newValue
      }
    }
  }
}

public class MedianCutPaletteBuilder<P: Palette>: PaletteBuilder where P.SampleType: Hashable {
  public typealias PaletteType = P
  public typealias SampleType = P.SampleType

  var samples = Set<SampleType>()
  let colors: UInt

  public init(colors: UInt) {
    self.colors = colors
  }

  public func addImage(_ image: CGImage) throws {
    guard let data = image.dataProvider?.data else {
      throw PNGError(message: "Unable to get data for image")
    }

    guard let dataPointer: UnsafePointer<UInt8> = CFDataGetBytePtr(data) else {
      throw PNGError(message: "Unable to get data pointer for image")
    }

    for i in 0..<image.height {
      for j in stride(from: 0, to: image.bytesPerRow, by: (image.bitsPerPixel / 8)) {
        let pointer = dataPointer.advanced(by: image.bytesPerRow * i + j)
        let data = UnsafeBufferPointer(start: pointer, count: 4)
        // TODO: We should pass the component order from CGImage
        let sample = SampleType(Array(data))
        samples.insert(sample)
      }
    }
  }

  public func toPalette() -> PaletteType {
    let cut = medianCut(Array(samples), colors: colors)
    return PaletteType(cut)
  }

  func medianCut<T: RandomAccessCollection>(_ samples: T, colors: UInt) -> [SampleType] where T.Iterator.Element == SampleType {
      // Median cut does this:
      // 1. Sort the list of samples by the component
      //    with the greatest range (spread) of values.
      // 2. Cut this sorted list in half.
      // 3. Recur log_2(palette size).
      var maxes: [SampleType.ComponentType: UInt8] = [:]
      var mins: [SampleType.ComponentType: UInt8] = [:]
      for sample in samples {
        for component in SampleType.componentTypes {
          let value = sample[component]
          let minValue = mins[component]
          if minValue == nil || value < minValue! {
            mins[component] = value
          }
          let maxValue = maxes[component]
          if maxValue == nil || value > maxValue! {
            maxes[component] = value
          }
        }
      }

      let mostSpread = SampleType.componentTypes.max { (lhs, rhs) -> Bool in
        let lhsSpread = maxes[lhs]! - mins[lhs]!
        let rhsSpread = maxes[rhs]! - mins[rhs]!
        return lhsSpread < rhsSpread
        }!

      let sorted = samples.sorted { (lhs: SampleType, rhs: SampleType) -> Bool in
        lhs[mostSpread] < rhs[mostSpread]
      }

    if 1 == colors {
      // Base case: average the remaining pixels.
      // TODO: Average
      return [sorted.last!]
    } else {
      let middle = sorted.count / 2
      let left = sorted[0..<middle]
      let right = sorted[middle..<sorted.count]
      return
        medianCut(left, colors: colors / 2) +
          medianCut(right, colors: colors / 2)
    }
  }
}

public class ManhattanDistancePalette<S: Sample>: Palette {
  public typealias SampleType = S

  public let colors: [SampleType]

  public required init(_ colors: [SampleType]) {
    self.colors = colors
  }

  public func convert(image: CGImage) -> CGImage {
    return image
  }
}
