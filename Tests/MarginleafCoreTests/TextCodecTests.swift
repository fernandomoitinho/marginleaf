import XCTest
@testable import MarginleafCore

final class TextCodecTests: XCTestCase {
    private func roundTrip(_ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        let data = Data(bytes)
        guard let decoded = TextCodec.decode(data) else {
            return XCTFail("decode failed", file: file, line: line)
        }
        let back = TextCodec.encode(decoded.text, usesCRLF: decoded.usesCRLF, hasBOM: decoded.hasBOM)
        XCTAssertEqual(back, data, "unchanged text must save back to identical bytes", file: file, line: line)
    }

    func testLFRoundTrip() { roundTrip(Array("# a\n\nb\n".utf8)) }
    func testNoTrailingNewlineRoundTrip() { roundTrip(Array("# a\n\nb".utf8)) }
    func testEmptyRoundTrip() { roundTrip([]) }
    func testCRLFRoundTrip() { roundTrip(Array("# a\r\n\r\nb\r\n".utf8)) }
    func testBOMRoundTrip() { roundTrip([0xEF, 0xBB, 0xBF] + Array("hi\n".utf8)) }
    func testBOMAndCRLFRoundTrip() { roundTrip([0xEF, 0xBB, 0xBF] + Array("a\r\nb\r\n".utf8)) }
    func testUnicodeRoundTrip() { roundTrip(Array("Olá — 日本語 🍃\n".utf8)) }

    func testCRLFIsNormalisedToLFInsideTheEditor() {
        let decoded = TextCodec.decode(Data("a\r\nb\r\n".utf8))
        XCTAssertEqual(decoded?.text, "a\nb\n")
        XCTAssertEqual(decoded?.usesCRLF, true)
    }

    func testBOMIsNotPartOfTheText() {
        let decoded = TextCodec.decode(Data([0xEF, 0xBB, 0xBF] + Array("hi".utf8)))
        XCTAssertEqual(decoded?.text, "hi")
        XCTAssertEqual(decoded?.hasBOM, true)
    }

    func testEditedTextKeepsCRLF() {
        let decoded = TextCodec.decode(Data("a\r\nb\r\n".utf8))!
        let out = TextCodec.encode(decoded.text + "c\n", usesCRLF: decoded.usesCRLF, hasBOM: decoded.hasBOM)
        XCTAssertEqual(out, Data("a\r\nb\r\nc\r\n".utf8))
    }

    func testInvalidUTF8IsRefused() {
        XCTAssertNil(TextCodec.decode(Data([0x68, 0xFF, 0x69])))
    }
}
