import XCTest
@testable import MarginleafCore

final class FenceScannerTests: XCTestCase {
    private func covered(_ text: String) -> [String] {
        let ns = text as NSString
        return FenceScanner.fenceRanges(in: text).map { ns.substring(with: $0) }
    }

    func testSimpleFence() {
        XCTAssertEqual(covered("a\n```\ncode\n```\nb\n"), ["```\ncode\n```\n"])
    }

    func testFenceWithLanguage() {
        XCTAssertEqual(covered("```swift\nlet x = 1\n```\n"), ["```swift\nlet x = 1\n```\n"])
    }

    func testTildeFence() {
        XCTAssertEqual(covered("~~~\nx\n~~~\n"), ["~~~\nx\n~~~\n"])
    }

    func testLongerFenceNeedsAtLeastAsLongCloser() {
        let text = "````\n```\ninner\n```\n````\nafter\n"
        XCTAssertEqual(covered(text), ["````\n```\ninner\n```\n````\n"])
    }

    func testDifferentMarkerDoesNotClose() {
        XCTAssertEqual(covered("```\na\n~~~\nb\n```\n"), ["```\na\n~~~\nb\n```\n"])
    }

    func testUnclosedFenceRunsToEnd() {
        XCTAssertEqual(covered("x\n```\nnever closed\nstill code"), ["```\nnever closed\nstill code"])
    }

    func testTwoFences() {
        XCTAssertEqual(covered("```\na\n```\ntext\n```\nb\n```\n"), ["```\na\n```\n", "```\nb\n```\n"])
    }

    func testFourSpaceIndentIsNotAFence() {
        XCTAssertEqual(covered("    ```\n    not a fence\n"), [])
    }

    func testTwoBackticksAreNotAFence() {
        XCTAssertEqual(covered("``\ntext\n``\n"), [])
    }

    func testNoFences() {
        XCTAssertEqual(covered("# Title\n\nJust text.\n"), [])
    }

    func testEmptyString() {
        XCTAssertEqual(covered(""), [])
    }
}
