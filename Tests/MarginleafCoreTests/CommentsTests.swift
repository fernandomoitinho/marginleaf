import XCTest
@testable import MarginleafCore

final class CommentsTests: XCTestCase {
    func testSidecarName() {
        let url = URL(fileURLWithPath: "/tmp/notes/plan.md")
        XCTAssertEqual(CommentStore.sidecarURL(for: url).lastPathComponent, "plan.md.comments.json")
    }

    func testSaveAndLoadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.md.comments.json")
        let c = Comment(quote: "two\nlines", body: "fix this", startLine: 3, endLine: 4)
        try CommentStore.save([c], noteName: "a.md", to: url)
        let loaded = CommentStore.load(from: url)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, c.id)
        XCTAssertEqual(loaded[0].quote, "two\nlines")
        XCTAssertEqual(loaded[0].endLine, 4)
    }

    func testSavingNoCommentsRemovesFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.md.comments.json")
        try CommentStore.save([Comment(quote: "x", body: "y", startLine: 1, endLine: 1)], noteName: "a.md", to: url)
        try CommentStore.save([], noteName: "a.md", to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMarkdownIsInDocumentOrder() {
        let late = Comment(quote: "later", body: "B", startLine: 20, endLine: 20)
        let early = Comment(quote: "first\nsecond", body: "A", startLine: 2, endLine: 3)
        let text = CommentFormatter.markdown(comments: [late, early], fileName: "n.md", filePath: "/x/n.md")
        XCTAssertTrue(text.contains("### 1 · lines 2–3"), text)
        XCTAssertTrue(text.contains("### 2 · line 20"), text)
        XCTAssertTrue(text.contains("> first\n> second"), text)
        XCTAssertTrue(text.contains("Total comments: 2"), text)
        XCTAssertLessThan(text.range(of: "first")!.lowerBound, text.range(of: "later")!.lowerBound)
    }

    func testOrphanIsFlagged() {
        let c = Comment(quote: "gone", body: "?", startLine: 5, endLine: 5)
        let text = CommentFormatter.markdown(comments: [c], orphanIDs: [c.id], fileName: "n.md", filePath: nil)
        XCTAssertTrue(text.contains("passage not found"), text)
    }

    func testSourcePositionsAreOptIn() {
        XCTAssertFalse(Renderer.html(from: "# T\n").contains("data-sourcepos"))
        XCTAssertTrue(Renderer.html(from: "# T\n\npara\n", sourcepos: true).contains("data-sourcepos=\"3:1-3:4\""))
    }
}

final class MarkdownPlainTests: XCTestCase {
    func testInlineMarkup() {
        XCTAssertEqual(MarkdownPlain.strip("**Bold** and `code` and [a link](http://x.y)"), "Bold and code and a link")
    }

    func testBlockMarkers() {
        XCTAssertEqual(MarkdownPlain.strip("## Heading"), "Heading")
        XCTAssertEqual(MarkdownPlain.strip("- [x] done"), "done")
        XCTAssertEqual(MarkdownPlain.strip("> quoted"), "quoted")
    }

    func testTableRowsDropSeparator() {
        let plain = MarkdownPlain.strip("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(plain.split(whereSeparator: \.isWhitespace).joined(separator: " "), "a b 1 2")
    }

    func testIntraWordUnderscoreKept() {
        XCTAssertEqual(MarkdownPlain.strip("snake_case_name"), "snake_case_name")
    }
}
