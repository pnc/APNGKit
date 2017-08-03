//
//  DisassemblerTests.swift
//  APNGKit
//
//  Copyright (c) 2016 Wei Wang <onevcat@gmail.com>
//  Copyright (c) 2017 Phil Calvin <phil@philcalvin.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import XCTest
@testable import APNGKit

class AassemblerTests: XCTestCase {
    func testWriteNoAnimation() throws {
        let metadata = APNGMeta(width: 2, height: 2, bitDepth: 8,
                                colorType: UInt32(PNG_COLOR_TYPE_RGB),
                                rowBytes: 2 * 8 * 3, frameCount: 2, playCount: 0, firstFrameHidden: false)
        let assembler = try Assembler(metadata: metadata)
        try assembler.addFrame(1)
        try assembler.addFrame(2)
        let data = assembler.encode()

        let disassembler = Disassembler(data: data)
        let meta = try disassembler.decodeMeta()
        XCTAssertEqual(2, meta.frameCount)
    }
}
