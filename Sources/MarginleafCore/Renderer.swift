import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown -> HTML using GitHub's cmark.
///
/// Raw HTML inside a note is dropped and `javascript:` links are stripped
/// (cmark's safe mode; we never pass the UNSAFE option), so a note can't
/// inject markup into the preview.
public enum Renderer {
    private static let extensions = ["table", "strikethrough", "autolink", "tasklist"]

    /// The HTML for the note body only (no <html>/<head>).
    /// With `sourcepos`, block elements carry `data-sourcepos="line:col-line:col"` so the preview
    /// can tell which lines of the Markdown a selection came from (used by comments).
    public static func html(from markdown: String, sourcepos: Bool = false) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        var options = CMARK_OPT_FOOTNOTES
        if sourcepos { options |= CMARK_OPT_SOURCEPOS }
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensions {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        markdown.withCString { cString in
            cmark_parser_feed(parser, cString, strlen(cString))
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        guard let rendered = cmark_render_html(
            document, options, cmark_parser_get_syntax_extensions(parser)
        ) else { return "" }
        defer { free(rendered) }

        return String(cString: rendered)
    }

    /// A complete page for the preview web view.
    ///
    /// The CSP blocks scripts and network fetches other than images, so even
    /// if something slipped through the sanitising it couldn't run.
    public static func page(from markdown: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src marginleaf: https: data:; style-src 'unsafe-inline'">
        <style>\(Style.css)</style>
        </head>
        <body>
        <article>
        \(html(from: markdown, sourcepos: true))
        </article>
        </body>
        </html>
        """
    }
}
