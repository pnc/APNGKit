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

  init() {
    print("lol")
  }

  func encode() throws -> Data {
    self.lastError = nil

    let safeSelf = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    var png_ptr_write = png_create_write_struct(PNG_LIBPNG_VER_STRING, safeSelf,
                                                errorCallback, errorCallback)
    var info_ptr_write = png_create_info_struct(png_ptr_write)
    let stream = OutputStream.toMemory()
    stream.open()
    let safeStream = UnsafeMutableRawPointer(Unmanaged.passUnretained(stream).toOpaque())
    png_set_write_fn(png_ptr_write, safeStream, { (pngPointer, bytes, length) in
      let voider = png_get_io_ptr(pngPointer)
      let stream = Unmanaged<OutputStream>.fromOpaque(voider!).takeUnretainedValue()
      stream.write(bytes!, maxLength: length)
    }, nil)
    let _ = threadsetjmp {
      png_set_IHDR(png_ptr_write, info_ptr_write, 2, 2,
                   8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
                   PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
      png_write_info(png_ptr_write, info_ptr_write)
//      png_set_acTL(png_ptr_write, info_ptr_write,
//                   2, // frames
//                   0) // plays
//
//      png_write_frame_head(<#T##png_ptr: png_structp!##png_structp!#>, <#T##info_ptr: png_infop!##png_infop!#>, <#T##row_pointers: png_bytepp!##png_bytepp!#>, <#T##width: png_uint_32##png_uint_32#>, <#T##height: png_uint_32##png_uint_32#>, <#T##x_offset: png_uint_32##png_uint_32#>, <#T##y_offset: png_uint_32##png_uint_32#>, <#T##delay_num: png_uint_16##png_uint_16#>, <#T##delay_den: png_uint_16##png_uint_16#>, <#T##dispose_op: png_byte##png_byte#>, <#T##blend_op: png_byte##png_byte#>)
//      png_write_frame_head(png_ptr_write, info_ptr_write, rowPointers,
//                           info_ptr_read->width,  /* width */
//        info_ptr_read->height, /* height */
//        0,       /* x offset */
//        0,       /* y offset */
//        1, 1,    /* delay numerator and denominator */
//        PNG_DISPOSE_OP_NONE, /* dispose */
//        PNG_BLEND_OP_SOURCE    /* blend */
//      );

                            //  R  G    B
      let pixels: [png_byte] = [0, 128, 255,
                                32, 32, 32]
      png_write_row(png_ptr_write, UnsafePointer(pixels))
      png_write_row(png_ptr_write, UnsafePointer(pixels))
      png_write_end(png_ptr_write, info_ptr_write)
      return 0
    }
    if let error = self.lastError {
      throw PNGError(message: error)
    }
    png_destroy_write_struct(&png_ptr_write, &info_ptr_write)
    stream.close()
    return stream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
  }
}
