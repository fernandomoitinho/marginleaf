import AppKit
import WebKit

/// Draws ```mermaid blocks as diagrams in the preview.
///
/// The preview page runs no scripts of its own, so this works from outside, like the comment
/// script does: mermaid is loaded into a separate content world, turns each block into an SVG,
/// and the SVG replaces the block. The library (a bundled 3.5 MB file) is only read and parsed
/// when a note actually contains a diagram. If a diagram has a mistake, its source stays visible
/// with the error as a tooltip. Nothing leaves the Mac.
enum MermaidRenderer {
    private static let world = WKContentWorld.world(name: "marginleaf-mermaid")

    private static let library: String? = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // The file ends with an assignment whose value WebKit cannot hand back; end on a number.
        return source + "\n;0"
    }()

    private static let countJS = "return document.querySelectorAll('pre > code.language-mermaid').length"

    private static let renderJS = """
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      suppressErrorRendering: true,
      theme: dark ? 'dark' : 'default',
      fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif'
    });
    const blocks = Array.from(document.querySelectorAll('pre > code.language-mermaid')).map(c => c.parentElement);
    let drawn = 0, failed = 0, n = 0;
    for (const pre of blocks) {
      const source = pre.textContent;
      try {
        const out = await mermaid.render('marginleaf-mermaid-' + (n++), source);
        pre.classList.add('mermaid-diagram');
        pre.innerHTML = out.svg;
        drawn++;
      } catch (e) {
        pre.classList.add('mermaid-error');
        pre.title = String((e && e.message) || e).slice(0, 400);
        failed++;
      }
    }
    return JSON.stringify({ blocks: blocks.length, drawn: drawn, failed: failed, svgs: document.querySelectorAll('pre.mermaid-diagram svg').length });
    """

    /// Calls back with the number of diagram blocks found (0 when there are none or the
    /// library is missing, as in a bare `swift run`).
    static func render(in webView: WKWebView, completion: @escaping (Int) -> Void) {
        webView.callAsyncJavaScript(countJS, arguments: [:], in: nil, in: world) { result in
            guard case .success(let value) = result, let count = value as? Int, count > 0,
                  let library else { completion(0); return }
            webView.evaluateJavaScript(library, in: nil, in: world) { loaded in
                guard case .success = loaded else { completion(0); return }
                let dark = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                webView.callAsyncJavaScript(renderJS, arguments: ["dark": dark], in: nil, in: world) { done in
                    if let path = ProcessInfo.processInfo.environment["MARGINLEAF_SELFTEST"] {
                        let text: String
                        switch done {
                        case .success(let value): text = "\(value)"
                        case .failure(let error): text = "ERROR: \(error)"
                        }
                        try? text.write(toFile: path + ".mermaid", atomically: true, encoding: .utf8)
                    }
                    completion(count)
                }
            }
        }
    }
}
