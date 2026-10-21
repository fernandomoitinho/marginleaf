import XCTest
@testable import MarginleafCore

final class OutlineTests: XCTestCase {
    func testAtxHeadingsWithLevelsAndLines() {
        let md = "# One\n\ntext\n\n## Two\n\n### Three\n"
        XCTAssertEqual(Outline.headings(in: md), [
            OutlineItem(level: 1, title: "One", line: 1),
            OutlineItem(level: 2, title: "Two", line: 5),
            OutlineItem(level: 3, title: "Three", line: 7),
        ])
    }

    func testUnderlinedHeadings() {
        let md = "Title\n=====\n\nSub\n---\n"
        XCTAssertEqual(Outline.headings(in: md), [
            OutlineItem(level: 1, title: "Title", line: 1),
            OutlineItem(level: 2, title: "Sub", line: 4),
        ])
    }

    func testHashesInsideFencedCodeAreIgnored() {
        let md = "# Real\n\n```\n# not a heading\n```\n\n## Also real\n"
        XCTAssertEqual(Outline.headings(in: md).map(\.title), ["Real", "Also real"])
    }

    func testInlineFormattingAndEntitiesBecomePlainText() {
        let md = "## A *very* `big` [link](https://example.com), Q&A and a < b\n"
        XCTAssertEqual(Outline.headings(in: md).first?.title, "A very big link, Q&A and a < b")
    }

    func testHeadingInsideBlockquoteIsListed() {
        let md = "intro\n\n> ## Quoted\n"
        XCTAssertEqual(Outline.headings(in: md), [OutlineItem(level: 2, title: "Quoted", line: 3)])
    }

    func testNoHeadings() {
        XCTAssertEqual(Outline.headings(in: "just text\n\n- a list\n"), [])
        XCTAssertEqual(Outline.headings(in: ""), [])
    }

    func testCRLFLinesMatch() {
        XCTAssertEqual(Outline.headings(in: "# A\r\n\r\n## B\r\n").map(\.line), [1, 3])
    }
}
