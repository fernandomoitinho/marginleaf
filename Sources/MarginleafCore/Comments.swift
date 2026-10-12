import Foundation

/// A comment attached to a highlighted passage of a note.
public struct Comment: Codable, Equatable, Identifiable {
    public var id: String
    /// The highlighted text, as the reader saw it in the preview.
    public var quote: String
    public var body: String
    /// Lines of the Markdown source the passage sits in (1-based). Refreshed whenever the
    /// preview finds the quote again after the file changed.
    public var startLine: Int
    public var endLine: Int
    public var createdAt: Date

    public init(id: String = UUID().uuidString, quote: String, body: String,
                startLine: Int, endLine: Int, createdAt: Date = Date()) {
        self.id = id
        self.quote = quote
        self.body = body
        self.startLine = startLine
        self.endLine = endLine
        self.createdAt = createdAt
    }
}

/// Comments live in a JSON file next to the note: `notes.md` → `notes.md.comments.json`.
public enum CommentStore {
    private struct FileFormat: Codable {
        var version: Int
        var file: String
        var comments: [Comment]
    }

    public static func sidecarURL(for note: URL) -> URL {
        note.appendingPathExtension("comments.json")
    }

    public static func load(from url: URL) -> [Comment] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(FileFormat.self, from: data))?.comments ?? []
    }

    /// Writes the file, or removes it when there are no comments left.
    public static func save(_ comments: [Comment], noteName: String, to url: URL) throws {
        if comments.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(FileFormat(version: 1, file: noteName, comments: comments))
        try data.write(to: url, options: .atomic)
    }
}

/// The text copied to the clipboard to hand the comments to someone (or an agent).
public enum CommentFormatter {
    public static func markdown(comments: [Comment], orphanIDs: Set<String> = [],
                                fileName: String, filePath: String?, generated: Date = Date()) -> String {
        let sorted = comments.sorted {
            ($0.startLine, $0.endLine, $0.createdAt) < ($1.startLine, $1.endLine, $1.createdAt)
        }
        var lines: [String] = []
        lines.append("# Comments on \(fileName)")
        lines.append("")
        if let filePath { lines.append("File: \(filePath)") }
        lines.append("Generated: \(ISO8601DateFormatter().string(from: generated))")
        lines.append("")
        lines.append("Each comment is attached to a highlighted passage. Line numbers refer to the Markdown file.")
        lines.append("")

        for (index, c) in sorted.enumerated() {
            let place = c.startLine == c.endLine ? "line \(c.startLine)" : "lines \(c.startLine)–\(c.endLine)"
            let orphan = orphanIDs.contains(c.id) ? " (passage not found, line numbers may be out of date)" : ""
            lines.append("### \(index + 1) · \(place)\(orphan)")
            lines.append(c.quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"))
            lines.append("")
            lines.append(c.body)
            lines.append("")
        }
        lines.append("---")
        lines.append("Total comments: \(sorted.count)")
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Turns a bit of Markdown source into the plain text the preview would show for it,
/// so a comment made in the Source view can still be found in the rendered page.
public enum MarkdownPlain {
    public static func strip(_ markdown: String) -> String {
        var out: [String] = []
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            // Table separator rows and horizontal rules show nothing.
            if line.contains("-"),
               line.range(of: #"^\s*\|?[\s:\-|]+\|?\s*$"#, options: .regularExpression) != nil { continue }
            line = line.replacingOccurrences(
                of: #"^\s*(#{1,6}\s+|>\s?|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#,
                with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            for mark in ["**", "__", "~~", "`"] { line = line.replacingOccurrences(of: mark, with: "") }
            line = line.replacingOccurrences(of: #"(?<!\w)[*_]|[*_](?!\w)"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "|", with: " ")
            out.append(line)
        }
        return out.joined(separator: " ")
    }
}
