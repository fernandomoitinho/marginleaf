import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// One piece of a note to read aloud: a heading, a paragraph, a table or a code block.
public struct SpeechSegment: Equatable {
    public enum Kind: Equatable { case heading, paragraph, table, code }

    public let kind: Kind
    /// What to say. Empty for `.code`: the app says its own short label, in the language of the note.
    public let text: String
    /// 1-based line in the Markdown source where the block starts.
    public let line: Int

    public init(kind: Kind, text: String, line: Int) {
        self.kind = kind
        self.text = text
        self.line = line
    }
}

/// Turns a note into the list of things worth hearing.
///
/// It walks the same cmark tree the preview is rendered from, so fences, tables, lists and
/// quotes behave as they do on screen. Code is not read out, links are read by their text
/// (a bare URL is skipped), images by their alt text, raw HTML and rules are ignored.
public enum SpeechPlan {
    private static let extensions = ["table", "strikethrough", "autolink", "tasklist"]

    public static func segments(from markdown: String) -> [SpeechSegment] {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_FOOTNOTES) else { return [] }
        defer { cmark_parser_free(parser) }
        for name in extensions {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        markdown.withCString { cmark_parser_feed(parser, $0, strlen($0)) }
        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }

        var out: [SpeechSegment] = []
        walk(document, into: &out)
        return out
    }

    // MARK: Blocks

    private static func walk(_ node: OpaquePointer, into out: inout [SpeechSegment]) {
        var child = cmark_node_first_child(node)
        while let block = child {
            let line = Int(cmark_node_get_start_line(block))
            switch typeName(block) {
            case "paragraph":
                add(.paragraph, inlineText(block), line, to: &out)
            case "heading":
                var text = inlineText(block)
                // A closing full stop gives the voice its pause between a title and what follows.
                if let last = text.last, !".:;!?".contains(last) { text += "." }
                add(.heading, text, line, to: &out)
            case "code_block":
                out.append(SpeechSegment(kind: .code, text: "", line: line))
            case "table":
                add(.table, tableText(block), line, to: &out)
            case "html_block", "thematic_break", "footnote_definition":
                break
            default:
                // Quotes, lists, list items, task items: look inside.
                walk(block, into: &out)
            }
            child = cmark_node_next(block)
        }
    }

    private static func add(_ kind: SpeechSegment.Kind, _ text: String, _ line: Int,
                            to out: inout [SpeechSegment]) {
        guard !text.isEmpty else { return }
        out.append(SpeechSegment(kind: kind, text: text, line: line))
    }

    private static func tableText(_ table: OpaquePointer) -> String {
        var rows: [String] = []
        var row = cmark_node_first_child(table)
        while let r = row {
            var cells: [String] = []
            var cell = cmark_node_first_child(r)
            while let c = cell {
                let text = inlineText(c)
                if !text.isEmpty { cells.append(text) }
                cell = cmark_node_next(c)
            }
            if !cells.isEmpty { rows.append(cells.joined(separator: ", ") + ".") }
            row = cmark_node_next(r)
        }
        return rows.joined(separator: " ")
    }

    // MARK: Inlines

    private static func inlineText(_ node: OpaquePointer) -> String {
        collapse(rawInline(node))
    }

    private static func rawInline(_ node: OpaquePointer) -> String {
        var result = ""
        var child = cmark_node_first_child(node)
        while let inline = child {
            switch typeName(inline) {
            case "text", "code":
                if let literal = cmark_node_get_literal(inline) { result += String(cString: literal) }
            case "softbreak", "linebreak":
                result += " "
            case "html_inline", "footnote_reference":
                break
            case "link":
                let label = rawInline(inline)
                let bare = collapse(label).lowercased()
                // An autolink's text is the address itself: nobody wants that read out.
                if !(bare.hasPrefix("http://") || bare.hasPrefix("https://") || bare.hasPrefix("www.")) {
                    result += label
                }
            default:
                // Emphasis, strong, strikethrough, images (their alt text), anything else with children.
                result += rawInline(inline)
            }
            child = cmark_node_next(inline)
        }
        return result
    }

    private static func typeName(_ node: OpaquePointer) -> String {
        guard let name = cmark_node_get_type_string(node) else { return "" }
        return String(cString: name)
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
