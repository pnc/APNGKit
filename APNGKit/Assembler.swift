import Foundation

func errorCallback(_ pngPointer: png_structp?, messagep: png_const_charp?) {
  if let messagep = messagep {
    let message = String(cString: messagep)
    debugPrint("horrible error: \(message)")
  } else {
    debugPrint("unknown error")
  }

  threadlongjmp(1)
}

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
  init() {
    print("lol")
  }

  func encode() -> Data {
    var png_ptr_write = png_create_write_struct(PNG_LIBPNG_VER_STRING, nil,
                                                errorCallback, errorCallback)
    var info_ptr_write = png_create_info_struct(png_ptr_write)
    threadsetjmp {
      png_write_end(png_ptr_write, info_ptr_write)
      return 0
    }

    return Data()
  }
}
