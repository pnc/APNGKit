import Foundation
import UIKit

public protocol Palette {
  associatedtype SampleType: Sample
  typealias Index = Int
  init(_ colors: [SampleType], cache: [SampleType:Index]?)
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
  init(data: Data)
  init(data: UnsafePointer<UInt8>)
  subscript(component: ComponentType) -> UInt8 { get }
  func distance(to: Self) -> Double
}

public enum RGBA {
  case R; case G; case B; case A
}

public struct RGBASample: Hashable, Equatable, Sample {
  public static var componentTypes = [RGBA.B, .G, .R, .A]

  var r: UInt8
  var g: UInt8
  var b: UInt8
  var a: UInt8

  public init(data: Data) {
    // Assuming BGRA
    self.init(r: data[2], g: data[1], b: data[0], a: data[3])
  }

  public init(data: UnsafePointer<UInt8>) {
    // Assuming BGRA
    self.init(r: data[2], g: data[1], b: data[0], a: data[3])
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

  public func distance(to sample: RGBASample) -> Double {
    var squares = 0.0
    squares += pow((Double(abs(Int32(r) - Int32(sample.r)))), 2)
    squares += pow((Double(abs(Int32(g) - Int32(sample.g)))), 2)
    squares += pow((Double(abs(Int32(b) - Int32(sample.b)))), 2)
    squares += pow((Double(abs(Int32(a) - Int32(sample.a)))), 2)
    return sqrt(squares)
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
        let sample = SampleType(data: Data(buffer: data))
        samples.insert(sample)
      }
    }
  }

  public func toPalette() -> PaletteType {
    var cut: [[SampleType]] = medianCut(Array(samples), colors: colors)
    var cache: [SampleType:Palette.Index] = [:]
    if PaletteType.SampleType.self == RGBASample.self {
      cut[0] = [RGBASample(r: 0, g: 0, b: 0, a: 0) as! P.SampleType]
    }
    let palette = cut.enumerated().map { (index, samples) -> SampleType in
      for sample in samples {
        cache[sample] = index
      }
      let middle = samples.count / 2
      return samples[middle]
    }
    return PaletteType(palette, cache: cache)
  }

  func medianCut<T: RandomAccessCollection>(_ samples: T, colors: UInt) -> [[SampleType]] where T.Iterator.Element == SampleType {
      // Median cut does this:
      // 1. Sort the list of samples by the component
      //    with the greatest range (spread) of values.
      // 2. Cut this sorted list in half.
      // 3. Recur log_2(palette size).
      var maxes: [SampleType.ComponentType: UInt8] = [:]
      var mins: [SampleType.ComponentType: UInt8] = [:]
      for component in SampleType.componentTypes {
        for sample in samples {
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
      // Base case: return all the samples that are left.
      // We do this rather than choosing the final sample to
      // 1) generalize the algorithm, since there are several
      //    approaches to the final sample selection that are
      //    better than just picking the median
      // 2) allow pre-populating the palette cache with all known
      //    samples, to save recomputing which cut they live in.
      return [sorted]
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
  fileprivate var colorCache: [SampleType:Palette.Index]

  public required init(_ colors: [SampleType], cache initialCache: [SampleType:Palette.Index]?) {
    self.colors = colors
    self.colorCache = initialCache ?? [:]
  }

  func bestIndex(for sample: SampleType) -> UInt8 {
    if colorCache[sample] == nil {
      var bestDistance: Double?
      var bestIndex: Int?
      //for (index, color) in self.colors.enumerated() {
      var index = 0
      for color in self.colors {
        //var squares = 0.0
//        for component in SampleType.componentTypes {
//          squares += pow((Double(sample[component]) - Double(color[component])), 2)
//        }
        //let rgbaSample = sample as! RGBASample
        //let rgbaColor = sample as! RGBASample
        //squares += pow((Double(sample[component]) - Double(color[component])), 2)
        //let distance = sqrt(squares)
        let distance = sample.distance(to: color)
        if bestDistance == nil || distance < bestDistance! {
          bestDistance = distance
          bestIndex = index
        }
        index += 1
      }
      colorCache[sample] = bestIndex
    }

    return UInt8(colorCache[sample]!)
  }

  public func convert(image: CGImage) -> CGImage {
    let bpp = SampleType.componentTypes.count
    assert(bpp == image.bitsPerPixel / 8)
    var rawColors: [UInt8] = Array(repeating: 0, count: self.colors.count * bpp)
    for (b, sample) in self.colors.enumerated() {
      for (c, component) in S.componentTypes.enumerated() {
        if component as! RGBA != .A {
          rawColors[b * (bpp - 1) + c] = sample[component]
        }
      }
    }
    let deviceRGB = CGColorSpaceCreateDeviceRGB()
    let colorspace = rawColors.withUnsafeBufferPointer { (pointer) -> CGColorSpace? in
      CGColorSpace(indexedBaseSpace: deviceRGB,
                   last: self.colors.count - 1,
                   colorTable: pointer.baseAddress!)
    }!

    let inputData = image.dataProvider!.data!
    let inputPtr = CFDataGetBytePtr(inputData)!
    var pixelData = Data(capacity: image.width * image.height)
    for i in 0..<image.height {
      var pixels: [UInt8] = Array(repeating: 0, count: image.width * 2)
      for (col, j) in stride(from: 0, to: image.bytesPerRow, by: bpp).enumerated() {
        let start = image.bytesPerRow * i + j
        let end = start + bpp

        // TODO: We should pass the component order from CGImage
        //let range = inputData[start..<end]

        //print("this: \(range[3])")
        let sample = SampleType(data: inputPtr.advanced(by: start))
        pixels[col] = bestIndex(for: sample)
        //pixels[col * 2 + 1] = (sample as! RGBASample)[.A]
      }
      pixelData.append(&pixels, count: image.width)
    }

    let provider = CGDataProvider(data: pixelData as CFData)!
    let info: CGBitmapInfo = []//[CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)]
    let new = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: image.width, space: colorspace, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent)!
    return new
  }
}
