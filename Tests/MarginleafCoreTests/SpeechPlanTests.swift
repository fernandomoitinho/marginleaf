import XCTest
@testable import MarginleafCore

final class SpeechPlanTests: XCTestCase {
    func testHeadingsAndParagraphsWithLines() {
        let md = "# Title\n\nFirst paragraph\nsecond line.\n\n## Part two\n\nMore text.\n"
        XCTAssertEqual(SpeechPlan.segments(from: md), [
            SpeechSegment(kind: .heading, text: "Title.", line: 1),
            SpeechSegment(kind: .paragraph, text: "First paragraph second line.", line: 3),
            SpeechSegment(kind: .heading, text: "Part two.", line: 6),
            SpeechSegment(kind: .paragraph, text: "More text.", line: 8),
        ])
    }

    func testHeadingKeepsItsOwnPunctuation() {
        XCTAssertEqual(SpeechPlan.segments(from: "# Why?\n").first?.text, "Why?")
    }

    func testCodeBlocksAreMarkedNotRead() {
        let md = "Before.\n\n```swift\nlet secret = 1\n```\n\nAfter.\n"
        let segments = SpeechPlan.segments(from: md)
        XCTAssertEqual(segments.map(\.kind), [.paragraph, .code, .paragraph])
        XCTAssertEqual(segments[1].text, "")
        XCTAssertFalse(segments.contains { $0.text.contains("secret") })
    }

    func testMermaidBlocksAreDiagramsNotCode() {
        let md = "```mermaid\nflowchart LR\n  A --> B\n```\n\n```sh\nls\n```\n"
        XCTAssertEqual(SpeechPlan.segments(from: md).map(\.kind), [.diagram, .code])
    }

    func testInlineFormattingIsStripped() {
        let md = "A **bold** and *soft* word, `code` and ~~gone~~ text.\n"
        XCTAssertEqual(SpeechPlan.segments(from: md).first?.text, "A bold and soft word, code and gone text.")
    }

    func testLinksReadTheirTextAndBareUrlsAreSkipped() {
        let md = "See [the docs](https://example.com/docs) or https://example.com/raw now.\n"
        XCTAssertEqual(SpeechPlan.segments(from: md).first?.text, "See the docs or now.")
    }

    func testImagesReadTheirAltText() {
        XCTAssertEqual(SpeechPlan.segments(from: "![A red barn](barn.png)\n").first?.text, "A red barn")
    }

    func testListsAndQuotesAreReadItemByItem() {
        let md = "- one\n- two\n\n> quoted words\n\n1. first\n2. second\n"
        XCTAssertEqual(SpeechPlan.segments(from: md).map(\.text), ["one", "two", "quoted words", "first", "second"])
    }

    func testTaskListItems() {
        XCTAssertEqual(SpeechPlan.segments(from: "- [x] done\n- [ ] todo\n").map(\.text), ["done", "todo"])
    }

    func testTableReadsRowByRow() {
        let md = "| Name | Age |\n|---|---|\n| Ana | 30 |\n| Rui | 41 |\n"
        let segments = SpeechPlan.segments(from: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .table)
        XCTAssertEqual(segments[0].text, "Name, Age. Ana, 30. Rui, 41.")
    }

    func testHtmlAndRulesAreIgnored() {
        let md = "<div>hidden</div>\n\n---\n\nShown.\n"
        XCTAssertEqual(SpeechPlan.segments(from: md).map(\.text), ["Shown."])
    }

    func testEmptyNoteHasNothingToSay() {
        XCTAssertEqual(SpeechPlan.segments(from: ""), [])
        XCTAssertEqual(SpeechPlan.segments(from: "\n\n"), [])
    }
}
