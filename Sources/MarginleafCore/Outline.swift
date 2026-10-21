import Foundation

/// One heading of a note, for the outline panel.
public struct OutlineItem: Equatable {
    /// 1...6, the number of `#` (or 1 / 2 for underlined headings).
    public let level: Int
    /// The heading as plain text: inline formatting removed.
    public let title: String
    /// 1-based line of the heading in the Markdown source.
    public let line: Int

    public init(level: Int, title: String, line: Int) {
        self.level = level
        self.title = title
        self.line = line
    }
}

/// The table of contents of a note.
///
/// Headings come from the same cmark pass that renders the preview, so fenced code,
/// underlined headings and headings inside quotes or lists are treated exactly as the
/// preview treats them, and every item's line matches the `data-sourcepos` in the page.
public enum Outline {
    private static let heading = try! NSRegularExpression(
        pattern: #"<h([1-6]) data-sourcepos="(\d+):\d+-\d+:\d+">(.*?)</h\1>"#,
        options: [.dotMatchesLineSeparators]
    )
    private static let tag = try! NSRegularExpression(pattern: "<[^>]*>")

    public static func headings(in markdown: String) -> [OutlineItem] {
        guard markdown.contains("#") || markdown.contains("\n=") || markdown.contains("\n-") else { return [] }
        let html = Renderer.html(from: markdown, sourcepos: true) as NSString
        var items: [OutlineItem] = []
        heading.enumerateMatches(in: html as String, range: NSRange(location: 0, length: html.length)) { match, _, _ in
            guard let match,
                  let level = Int(html.substring(with: match.range(at: 1))),
                  let line = Int(html.substring(with: match.range(at: 2))) else { return }
            let title = plainText(html.substring(with: match.range(at: 3)))
            if !title.isEmpty { items.append(OutlineItem(level: level, title: title, line: line)) }
        }
        return items
    }

    /// Inline HTML to plain text: drop tags, undo the escaping cmark applies, collapse whitespace.
    static func plainText(_ html: String) -> String {
        let stripped = tag.stringByReplacingMatches(
            in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
        let decoded = stripped
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        return decoded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
