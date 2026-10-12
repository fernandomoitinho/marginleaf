import XCTest
@testable import MarginleafCore

final class RendererTests: XCTestCase {
    func testHeadingAndParagraph() {
        let html = Renderer.html(from: "# Title\n\nHello **world**.\n")
        XCTAssertTrue(html.contains("<h1>Title</h1>"), html)
        XCTAssertTrue(html.contains("<strong>world</strong>"), html)
    }

    func testTable() {
        let md = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let html = Renderer.html(from: md)
        XCTAssertTrue(html.contains("<table>"), html)
        XCTAssertTrue(html.contains("<td>1</td>") || html.contains("<td>1 </td>"), html)
    }

    func testTaskList() {
        let html = Renderer.html(from: "- [x] done\n- [ ] todo\n")
        XCTAssertTrue(html.contains("type=\"checkbox\""), html)
        XCTAssertTrue(html.contains("checked"), html)
    }

    func testStrikethroughAndAutolink() {
        let html = Renderer.html(from: "~~gone~~ and https://example.com\n")
        XCTAssertTrue(html.contains("<del>gone</del>"), html)
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">"), html)
    }

    func testFootnote() {
        let html = Renderer.html(from: "Text[^1]\n\n[^1]: The note.\n")
        XCTAssertTrue(html.contains("footnote"), html)
        XCTAssertTrue(html.contains("The note."), html)
    }

    func testRawScriptIsNotPassedThrough() {
        let html = Renderer.html(from: "Hi\n\n<script>alert(1)</script>\n")
        XCTAssertFalse(html.lowercased().contains("<script"), html)
    }

    func testInlineHTMLIsNotPassedThrough() {
        let html = Renderer.html(from: "x <img src=x onerror=alert(1)> y\n")
        XCTAssertFalse(html.lowercased().contains("onerror"), html)
    }

    func testJavascriptLinkIsStripped() {
        let html = Renderer.html(from: "[click](javascript:alert(1))\n")
        XCTAssertFalse(html.lowercased().contains("javascript:"), html)
    }

    func testPageHasCSPAndNoScript() {
        let page = Renderer.page(from: "# Hi\n")
        XCTAssertTrue(page.hasPrefix("<!doctype html>"))
        XCTAssertTrue(page.contains("Content-Security-Policy"))
        XCTAssertFalse(page.lowercased().contains("<script"))
        XCTAssertTrue(page.contains(">Hi</h1>"))
    }

    func testEmptyInput() {
        XCTAssertEqual(Renderer.html(from: ""), "")
    }

    func testUnicodeSurvives() {
        let html = Renderer.html(from: "# Marginleaf, à vista — 日本語 🍃\n")
        XCTAssertTrue(html.contains("Marginleaf, à vista — 日本語 🍃"), html)
    }

    func testOneMegabyteRendersQuickly() {
        var md = ""
        var i = 0
        while md.utf8.count < 1_000_000 {
            md += "## Section \(i)\n\nSome *emphasis*, **bold**, `code` and a [link](https://example.com/\(i)).\n\n- one\n- two\n\n"
            i += 1
        }
        let start = Date()
        let html = Renderer.html(from: md)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(html.utf8.count, md.utf8.count / 2)
        // Typically a few tens of milliseconds; the bound is generous for CI noise.
        XCTAssertLessThan(elapsed, 2.0, "1 MB took \(elapsed)s")
    }
}
