import AppKit
import UniformTypeIdentifiers
import WebKit

/// Serves images next to the open note to the preview, under `marginleaf://doc/...`.
///
/// The web view never gets file access. Only image files inside the note's own
/// folder (or below it) are handed over, and `..` can't climb out of it.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    var root: URL?

    /// Maps `marginleaf://doc/some/path` to a file under `root`, or nil if it escapes.
    func fileURL(for url: URL) -> URL? {
        guard let root else { return nil }
        let rootPath = root.standardizedFileURL.path
        let relative = String(url.path.dropFirst()) // url.path is already percent-decoded
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let path = candidate.path
        guard path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            return nil
        }
        return candidate
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let file = fileURL(for: url),
              let type = UTType(filenameExtension: file.pathExtension),
              type.conforms(to: .image),
              let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: type.preferredMIMEType ?? "application/octet-stream",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
