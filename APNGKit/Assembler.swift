import Foundation

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

public class Assembler {
  var lastError: String?
  var png_ptr_write: png_structp
  var info_ptr_write: png_structp
  let stream = OutputStream.toMemory()

  init(metadata: APNGMeta) throws {
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
    let _ = threadsetjmp {
      png_set_IHDR(png_ptr_write, info_ptr_write, metadata.width, metadata.height,
                   Int32(metadata.bitDepth), PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
                   PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
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

  func addFrame(_ num: Int) throws {
    let _ = threadsetjmp { () -> Int in
      png_write_frame_head(png_ptr_write, info_ptr_write,
                           nil, 2, 2,
                           0, 0,
                           1, 2,
                           png_byte(PNG_DISPOSE_OP_NONE),
                           png_byte(PNG_BLEND_OP_SOURCE))

      //  R  G    B
      var pixels: [png_byte]
      switch num {
      case 1:
        pixels = [0, 128, 255,
                  32, 32, 32]
      default:
        pixels = [32, 32, 32,
                  0, 128, 255]
      }

      png_write_row(png_ptr_write, UnsafePointer(pixels))
      png_write_row(png_ptr_write, UnsafePointer(pixels))
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

  func encode() -> Data {
    png_write_end(png_ptr_write, info_ptr_write)
    stream.close()
    return stream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
  }
}
