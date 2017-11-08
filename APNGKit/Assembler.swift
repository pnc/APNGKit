import Foundation
import UIKit

struct PNGError : Error {
  let message: String
  func debugDescription() -> String {
    return "<PNGError \(message)>"
  }
}

func errorCallback(_ pngPointer: png_structp?, messagep: png_const_charp?) {
  let message: String = {
    if let messagep = messagep {
      return String(cString: messagep)
    } else {
      return "unknown"
    }
  }()
  let voider = png_get_error_ptr(pngPointer)
  let assembler = Unmanaged<Assembler>.fromOpaque(voider!)
  print("libpng error: \(message)")
  assembler.takeUnretainedValue().lastError = message
  threadlongjmp(1)
}

// This is beautiful and it is not mine.
// https://github.com/mattgallagher/CwlPreconditionTesting/issues/7#issuecomment-282164048
func threadsetjmp(_ body: () -> Int) -> Int {
  return withoutActuallyEscaping(body) { body in
    var body2 = body
    return withUnsafeMutableBytes(of: &body2) { rawBody in

      var thread: pthread_t?
      let errno = pthread_create(&thread, nil, { rawContext in
        let body = rawContext.load(as: (() -> Int).self)
        let result = body()
        return UnsafeMutableRawPointer(bitPattern: result)
      }, rawBody.baseAddress)
      assert(errno == 0)

      var rawResult: UnsafeMutableRawPointer?
      let errno2 = pthread_join(thread!, &rawResult)
      assert(errno2 == 0)
      return Int(bitPattern: rawResult)
    }
  }
}

func threadlongjmp(_ result: Int) -> Never {
  // pthread_exit still leaks since Swift emits no unwind info, but doesn't
  // have the local semantics problems of setjmp/longjmp...
  pthread_exit(UnsafeMutableRawPointer(bitPattern: result))
}

public struct RationalDuration {
  let numerator: UInt16
  let denominator: UInt16

  public init(_ num: UInt16, _ den: UInt16) {
    self.numerator = num
    self.denominator = den
  }
}

public struct Point {
  let x: UInt32
  let y: UInt32
  public init(x: UInt32, y: UInt32) {
    self.x = x
    self.y = y
  }
}

public struct APNGFrame {
  let image: UIImage
  let offset: Point
  let duration: RationalDuration
  let disposeOperation: DisposeOperation
  let blendOperation: BlendOperation

  public init(image: UIImage, duration: RationalDuration,
       offset: Point = Point(x: 0, y: 0),
       disposeOperation: DisposeOperation = .background,
       blendOperation: BlendOperation = .source) {
    self.image = image
    self.offset = offset
    self.duration = duration
    self.disposeOperation = disposeOperation
    self.blendOperation = blendOperation
  }

  public enum DisposeOperation {
    case none
    case previous
    case background

    // Can't use real rawValues because those have to be literals.
    var rawValue: png_byte {
      switch self {
      case .none: return png_byte(PNG_DISPOSE_OP_NONE)
      case .background: return png_byte(PNG_DISPOSE_OP_BACKGROUND)
      case .previous: return png_byte(PNG_DISPOSE_OP_PREVIOUS)
      }
    }
  }

  public enum BlendOperation {
    case source
    case over

    // Can't use real rawValues because those have to be literals.
    var rawValue: png_byte {
      switch self {
      case .source: return png_byte(PNG_BLEND_OP_SOURCE)
      case .over: return png_byte(PNG_BLEND_OP_OVER)
      }
    }
  }
}

public class Assembler {
  var lastError: String?
  var png_ptr_write: png_structp
  var info_ptr_write: png_structp
  let stream = OutputStream.toMemory()

  public init<P: Palette>(metadata: APNGMeta, palette: P? = nil) throws
    where P.SampleType == RGBASample {
    png_ptr_write = png_create_write_struct(PNG_LIBPNG_VER_STRING,
                                            nil, nil, nil)
    info_ptr_write = png_create_info_struct(png_ptr_write)
    let safeSelf = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    png_set_error_fn(png_ptr_write, safeSelf, errorCallback, errorCallback)

    stream.open()
    let safeStream = UnsafeMutableRawPointer(Unmanaged.passUnretained(stream).toOpaque())
    png_set_write_fn(png_ptr_write, safeStream, { (pngPointer, bytes, length) in
      let voider = png_get_io_ptr(pngPointer)
      let stream = Unmanaged<OutputStream>.fromOpaque(voider!).takeUnretainedValue()
      stream.write(bytes!, maxLength: length)
    }, nil)
    png_set_flush(png_ptr_write, 0)
    let _ = threadsetjmp {
      let colorType = palette == nil ? Int32(metadata.colorType) : PNG_COLOR_TYPE_PALETTE
      png_set_IHDR(png_ptr_write, info_ptr_write, metadata.width, metadata.height,
                   Int32(metadata.bitDepth), colorType, PNG_INTERLACE_NONE,
                   PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

      if let palette = palette {
        let colors = palette.colors.map { sample in
          png_color_struct(red: sample.r, green: sample.g, blue: sample.b)
        }
        let trans = palette.colors.map { $0.a }
        png_set_PLTE(png_ptr_write, info_ptr_write,
                     colors, Int32(palette.colors.count))
        png_set_tRNS(png_ptr_write, info_ptr_write,
                     trans, Int32(palette.colors.count), nil)
      }

      png_set_compression_level(png_ptr_write, 9);
      png_set_compression_buffer_size(png_ptr_write, 8192 * 4)
      png_set_bgr(png_ptr_write)
      png_set_acTL(png_ptr_write, info_ptr_write,
                   metadata.frameCount, metadata.playCount)
      png_write_info(png_ptr_write, info_ptr_write)
      return 0
    }
    if let error = self.lastError {
      self.lastError = nil
      throw PNGError(message: error)
    }
  }

  public func addFrame(_ frame: APNGFrame) throws {
    let _ = threadsetjmp { () -> Int in
      guard let cgImage = frame.image.cgImage,
        let data = cgImage.dataProvider?.data else {
          self.lastError = "Unable to get image data for frame"
          threadlongjmp(1)
      }

      png_write_frame_head(png_ptr_write, info_ptr_write,
                           nil, png_uint_32(cgImage.width), png_uint_32(cgImage.height),
                           frame.offset.x, frame.offset.y,
                           frame.duration.numerator, frame.duration.denominator,
                           frame.disposeOperation.rawValue,
                           frame.blendOperation.rawValue)

      guard let dataPointer: UnsafePointer<UInt8> = CFDataGetBytePtr(data) else {
        self.lastError = "Unable to get byte pointer for image data"
        threadlongjmp(2)
      }
      
      let rowBytes = png_get_rowbytes(png_ptr_write, info_ptr_write)
      // CGImage seems round up, presumably for alignment reasons, so sometimes
      // it will have more bytes than we need.
      assert(rowBytes <= cgImage.bytesPerRow)
      for i in 0..<cgImage.height {
        png_write_row(png_ptr_write, dataPointer.advanced(by: cgImage.bytesPerRow * i))
      }
      png_write_frame_tail(png_ptr_write, info_ptr_write)
      return 0
    }
    if let error = self.lastError {
      self.lastError = nil
      throw PNGError(message: error)
    }
  }

  deinit {
    png_destroy_write_struct(UnsafeMutablePointer(png_ptr_write),
                             UnsafeMutablePointer(info_ptr_write))
  }

  public func encode() -> Data {
    png_write_end(png_ptr_write, info_ptr_write)
    stream.close()
    return stream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
  }
}
