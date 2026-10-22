import AppKit
import WebKit
import MarginleafCore

/// Keeps the scripts injected into the preview from retaining the controller.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

/// Comments on the preview: select text, comment, highlight, copy them all.
/// The page scripts stay off; our own script runs in a separate content world.
final class CommentsController: NSObject, WKScriptMessageHandler {
    private(set) var comments: [Comment] = []
    private var orphanIDs: Set<String> = []
    private let initialURL: URL?
    private var popover: NSPopover?

    weak var webView: WKWebView?
    weak var textView: NSTextView?
    weak var window: NSWindow?
    var onChange: (() -> Void)?

    private var noteURL: URL? { window?.representedURL ?? initialURL }

    init(noteURL: URL?) {
        initialURL = noteURL
        super.init()
        if let noteURL {
            comments = CommentStore.load(from: CommentStore.sidecarURL(for: noteURL))
        }
    }

    func install(in config: WKWebViewConfiguration) {
        let content = config.userContentController
        content.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: true, in: .defaultClient))
        content.add(WeakScriptHandler(self), contentWorld: .defaultClient, name: "marginleaf")
    }

    var hasComments: Bool { !comments.isEmpty }

    // MARK: Adding

    func beginAdd() {
        guard let webView else { return }
        webView.evaluateJavaScript("marginleafSelection()", in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result,
                  let info = value as? [String: Any],
                  let text = info["text"] as? String,
                  case let quote = text.trimmingCharacters(in: .whitespacesAndNewlines),
                  !quote.isEmpty
            else {
                self.hint("Select some text in the preview first.")
                NSSound.beep()
                return
            }
            let start = (info["start"] as? Int) ?? 1
            let end = max(start, (info["end"] as? Int) ?? start)
            self.addFromPreview(quote: quote, start: start, end: end, rect: self.rect(from: info))
        }
    }

    private func addFromPreview(quote: String, start: Int, end: Int, rect: NSRect) {
        present(quote: quote, body: "", isNew: true, rect: rect) { body in
            self.comments.append(Comment(quote: quote, body: body, startLine: start, endLine: end))
            self.save()
            self.applyHighlights()
            self.applySourceHighlights()
        } onDelete: {}
    }

    // MARK: Highlights

    /// Hides or shows the yellow marks without touching the comments themselves.
    func applyVisibility() {
        webView?.evaluateJavaScript("marginleafSetVisible(\(Settings.commentsVisible))", in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// Marks every comment's quote in the freshly rendered page, and learns where each one
    /// sits now (the file may have changed since the comment was written).
    func applyHighlights() {
        guard let webView else { return }
        let payload: [[String: Any]] = comments.map {
            ["id": $0.id, "quote": $0.quote, "alt": MarkdownPlain.strip($0.quote), "start": $0.startLine]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("marginleafHighlight(\(json))", in: nil, in: .defaultClient) { [weak self] result in
            guard let self, case .success(let value) = result, let items = value as? [[String: Any]] else { return }
            var changed = false
            var orphans = Set<String>()
            for item in items {
                guard let id = item["id"] as? String,
                      let i = self.comments.firstIndex(where: { $0.id == id }) else { continue }
                if (item["found"] as? Bool) == true {
                    if let s = item["start"] as? Int, let e = item["end"] as? Int,
                       s != self.comments[i].startLine || e != self.comments[i].endLine {
                        self.comments[i].startLine = s
                        self.comments[i].endLine = e
                        changed = true
                    }
                } else {
                    orphans.insert(id)
                }
            }
            self.orphanIDs = orphans
            self.applyVisibility()
            if changed { self.save() }
            self.onChange?()
        }
    }

    // MARK: Clicks on a highlight

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "add" {
            // A click on a hovered block: comment on a whole paragraph, list item, table...
            guard let text = body["text"] as? String,
                  case let quote = text.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty else { return }
            let start = (body["start"] as? Int) ?? 1
            addFromPreview(quote: quote, start: start, end: max(start, (body["end"] as? Int) ?? start), rect: rect(from: body))
            return
        }
        guard type == "click", let id = body["id"] as? String,
              let comment = comments.first(where: { $0.id == id }) else { return }
        edit(comment, rect: rect(from: body))
    }

    private func edit(_ comment: Comment, rect: NSRect, in view: NSView? = nil) {
        present(quote: comment.quote, body: comment.body, isNew: false, rect: rect, in: view) { [weak self] body in
            guard let self, let i = self.comments.firstIndex(where: { $0.id == comment.id }) else { return }
            self.comments[i].body = body
            self.save()
            self.onChange?()
        } onDelete: { [weak self] in
            guard let self else { return }
            self.comments.removeAll { $0.id == comment.id }
            self.save()
            self.applyHighlights()
            self.applySourceHighlights()
        }
    }

    // MARK: Source view

    private static func lineStarts(_ text: NSString) -> [Int] {
        var starts = [0]
        var i = 0
        let n = text.length
        while i < n {
            if text.character(at: i) == 0x0A { starts.append(i + 1) }
            i += 1
        }
        return starts
    }

    /// 1-based line of a character offset.
    private static func line(of location: Int, in starts: [Int]) -> Int {
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    /// Where a comment sits in the source: the exact text if it's there (nearest to the
    /// remembered line), otherwise the whole lines it was recorded on.
    private func sourceRange(for c: Comment, in text: NSString, lineStarts: [Int]) -> NSRange? {
        if !c.quote.isEmpty {
            var best: NSRange?
            var bestDist = Int.max
            var search = NSRange(location: 0, length: text.length)
            while search.length > 0 {
                let r = text.range(of: c.quote, options: [], range: search)
                if r.location == NSNotFound { break }
                let d = abs(Self.line(of: r.location, in: lineStarts) - c.startLine)
                if d < bestDist { best = r; bestDist = d }
                let next = r.location + 1
                search = NSRange(location: next, length: text.length - next)
            }
            if let best { return best }
        }
        let first = max(1, c.startLine), last = max(first, c.endLine)
        guard first <= lineStarts.count else { return nil }
        let from = lineStarts[first - 1]
        var to = last < lineStarts.count ? lineStarts[last] : text.length
        if to > from, text.character(at: to - 1) == 0x0A { to -= 1 }
        return to > from ? NSRange(location: from, length: to - from) : nil
    }

    private func sourceRect(for range: NSRange, in tv: NSTextView) -> NSRect {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return .zero }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var r = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        r.origin.x += tv.textContainerOrigin.x
        r.origin.y += tv.textContainerOrigin.y
        r.size.width = max(1, r.width)
        r.size.height = max(1, r.height)
        return r
    }

    /// Yellow background behind each comment in the source (a display-only attribute, never
    /// part of the text, the undo stack or the saved file).
    func applySourceHighlights() {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let text = tv.string as NSString
        let full = NSRange(location: 0, length: text.length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        guard Settings.commentsVisible, !comments.isEmpty else { return }
        let starts = Self.lineStarts(text)
        let color = NSColor.systemYellow.withAlphaComponent(0.35)
        var changed = false
        for i in comments.indices {
            let c = comments[i]
            guard let range = sourceRange(for: c, in: text, lineStarts: starts) else { continue }
            lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            // Exact match: keep the recorded lines current.
            if !c.quote.isEmpty, text.substring(with: range) == c.quote {
                let s = Self.line(of: range.location, in: starts)
                let e = Self.line(of: max(range.location, NSMaxRange(range) - 1), in: starts)
                if s != c.startLine || e != c.endLine {
                    comments[i].startLine = s
                    comments[i].endLine = e
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    func beginAddFromSource() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else {
            hint("Select some text in the source first.")
            NSSound.beep()
            return
        }
        let text = tv.string as NSString
        let quote = text.substring(with: range)
        let starts = Self.lineStarts(text)
        let start = Self.line(of: range.location, in: starts)
        let end = Self.line(of: max(range.location, NSMaxRange(range) - 1), in: starts)
        present(quote: quote, body: "", isNew: true, rect: sourceRect(for: range, in: tv), in: tv) { body in
            self.comments.append(Comment(quote: quote, body: body, startLine: start, endLine: end))
            self.save()
            self.applySourceHighlights()
            self.applyHighlights()
        } onDelete: {}
    }

    /// A plain click inside a highlighted passage opens that comment.
    func sourceClicked(at point: NSPoint) {
        guard let tv = textView, Settings.commentsVisible, tv.selectedRange().length == 0 else { return }
        let index = tv.characterIndexForInsertion(at: point)
        let text = tv.string as NSString
        let starts = Self.lineStarts(text)
        for c in comments {
            guard let range = sourceRange(for: c, in: text, lineStarts: starts),
                  index >= range.location, index < NSMaxRange(range) else { continue }
            edit(c, rect: sourceRect(for: range, in: tv), in: tv)
            return
        }
    }

    // MARK: Menu (toolbar)

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let copy = NSMenuItem(title: comments.isEmpty ? "Copy All Comments" : "Copy All Comments (\(comments.count))",
                              action: #selector(copyAll), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = !comments.isEmpty
        menu.addItem(copy)
        if comments.isEmpty {
            let none = NSMenuItem(title: "No comments yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return menu
        }
        menu.addItem(.separator())
        for c in comments.sorted(by: { ($0.startLine, $0.createdAt) < ($1.startLine, $1.createdAt) }) {
            let title = "\(Self.short(c.quote, 28)) — \(Self.short(c.body, 40))"
            let item = NSMenuItem(title: title, action: #selector(focusComment(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let all = NSMenuItem(title: "Delete All Comments…", action: #selector(deleteAll), keyEquivalent: "")
        all.target = self
        menu.addItem(all)
        return menu
    }

    private static func short(_ text: String, _ limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    @objc func copyAll() {
        guard !comments.isEmpty else { return }
        let url = noteURL
        let text = CommentFormatter.markdown(
            comments: comments, orphanIDs: orphanIDs,
            fileName: url?.lastPathComponent ?? "Untitled", filePath: url?.path
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hint("Copied \(comments.count) comment\(comments.count == 1 ? "" : "s")")
    }

    @objc private func focusComment(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let comment = comments.first(where: { $0.id == id }) else { return }
        if let tv = textView, webView?.isHidden == true {
            let text = tv.string as NSString
            guard let range = sourceRange(for: comment, in: text, lineStarts: Self.lineStarts(text)) else {
                hint("That passage is no longer in the note.")
                return
            }
            tv.scrollRangeToVisible(range)
            tv.showFindIndicator(for: range)
            edit(comment, rect: sourceRect(for: range, in: tv), in: tv)
            return
        }
        webView?.evaluateJavaScript("marginleafFocus(\(Self.jsString(id)))", in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            if case .success(let value) = result, let info = value as? [String: Any] {
                self.edit(comment, rect: self.rect(from: info))
            } else {
                self.hint("That passage is no longer in the note.")
            }
        }
    }

    @objc private func deleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all \(comments.count) comments?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        comments.removeAll()
        save()
        applyHighlights()
    }

    // MARK: Helpers

    private func present(quote: String, body: String, isNew: Bool, rect: NSRect, in view: NSView? = nil,
                         onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        guard let anchor = view ?? webView else { return }
        popover?.close()
        let editor = CommentEditor(
            quote: quote, body: body, canDelete: !isNew,
            onSave: { [weak self] text in self?.popover?.close(); onSave(text) },
            onDelete: { [weak self] in self?.popover?.close(); onDelete() },
            onCancel: { [weak self] in self?.popover?.close() }
        )
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = editor
        pop.show(relativeTo: rect, of: anchor, preferredEdge: .maxY)
        popover = pop
    }

    /// A rectangle reported by the page (CSS pixels) in the web view's own coordinates.
    private func rect(from info: [String: Any]) -> NSRect {
        let zoom = webView?.pageZoom ?? 1
        func n(_ key: String) -> CGFloat { CGFloat((info[key] as? Double) ?? 0) * CGFloat(zoom) }
        return NSRect(x: n("x"), y: n("y"), width: max(1, n("w")), height: max(1, n("h")))
    }

    private func save() {
        guard let url = noteURL else { return }
        do {
            try CommentStore.save(comments, noteName: url.lastPathComponent, to: CommentStore.sidecarURL(for: url))
        } catch {
            hint("Couldn't save comments: \(error.localizedDescription)")
        }
        onChange?()
    }

    private func hint(_ text: String) {
        window?.subtitle = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.window?.subtitle == text { self?.window?.subtitle = "" }
        }
    }

    private static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    // MARK: The script that runs inside the preview

    static let script = """
    (function () {
      var art = function () { return document.querySelector('article'); };
      function blockOf(node) {
        var e = node && node.nodeType === 1 ? node : (node ? node.parentElement : null);
        while (e && !(e.hasAttribute && e.hasAttribute('data-sourcepos'))) e = e.parentElement;
        return e;
      }
      function lines(e) {
        if (!e) return null;
        var m = /^(\\d+):\\d+-(\\d+):\\d+$/.exec(e.getAttribute('data-sourcepos'));
        return m ? [+m[1], +m[2]] : null;
      }
      function box(r) { return { x: r.left, y: r.top, w: r.width, h: r.height }; }

      window.marginleafSelection = function () {
        var s = window.getSelection();
        if (!s || s.isCollapsed || !s.rangeCount) return null;
        var r = s.getRangeAt(0), a = art();
        if (!a || !a.contains(r.commonAncestorContainer)) return null;
        var from = lines(blockOf(r.startContainer)), to = lines(blockOf(r.endContainer));
        var b = box(r.getBoundingClientRect());
        b.text = s.toString();
        b.start = from ? from[0] : 1;
        b.end = to ? to[1] : (from ? from[1] : 1);
        return b;
      };

      function clearMarks() {
        var marks = document.querySelectorAll('mark.fc');
        for (var i = 0; i < marks.length; i++) {
          var m = marks[i], p = m.parentNode;
          while (m.firstChild) p.insertBefore(m.firstChild, m);
          p.removeChild(m);
          p.normalize();
        }
      }

      function flatten() {
        var walker = document.createTreeWalker(art(), NodeFilter.SHOW_TEXT, null);
        var text = '', map = [], lastSpace = true, n;
        while ((n = walker.nextNode())) {
          var t = n.nodeValue;
          for (var i = 0; i < t.length; i++) {
            if (/\\s/.test(t[i])) {
              if (!lastSpace) { text += ' '; map.push([n, i]); lastSpace = true; }
            } else { text += t[i]; map.push([n, i]); lastSpace = false; }
          }
        }
        return { text: text, map: map };
      }

      function squash(s) { return s.replace(/\\s+/g, ' ').trim(); }

      function locate(flat, q, start) {
        var best = -1, bestDist = Infinity, at = q ? flat.text.indexOf(q) : -1;
        while (at !== -1) {
          var l = lines(blockOf(flat.map[at][0]));
          var d = Math.abs((l ? l[0] : 0) - start);
          if (d < bestDist) { bestDist = d; best = at; }
          at = flat.text.indexOf(q, at + 1);
        }
        return best;
      }

      window.marginleafHighlight = function (items) {
        if (!art()) return [];
        clearMarks();
        var results = [];
        for (var k = 0; k < items.length; k++) {
          var item = items[k], q = squash(item.quote), flat = flatten();
          var best = locate(flat, q, item.start);
          if (best === -1 && item.alt) { q = squash(item.alt); best = locate(flat, q, item.start); }
          var last;
          if (best === -1 && q.length > 60) {
            // The passage was edited: if its opening is still there, mark the rest of that block.
            var head = q.slice(0, 50);
            best = locate(flat, head, item.start);
            if (best !== -1) {
              var blk = blockOf(flat.map[best][0]);
              last = best + head.length - 1;
              while (last + 1 < flat.map.length && blockOf(flat.map[last + 1][0]) === blk) last++;
            }
          } else if (best !== -1) {
            last = best + q.length - 1;
          }
          if (best === -1) { results.push({ id: item.id, found: false }); continue; }

          var parts = [];
          for (var i = best; i <= last; i++) {
            var entry = flat.map[i], tail = parts[parts.length - 1];
            if (tail && tail.node === entry[0]) tail.end = entry[1] + 1;
            else parts.push({ node: entry[0], start: entry[1], end: entry[1] + 1 });
          }
          var first = lines(blockOf(parts[0].node)), lastBlock = lines(blockOf(parts[parts.length - 1].node));
          for (var j = 0; j < parts.length; j++) {
            var p = parts[j];
            if (!p.node.nodeValue.slice(p.start, p.end).trim()) continue;
            var range = document.createRange();
            range.setStart(p.node, p.start);
            range.setEnd(p.node, p.end);
            var mark = document.createElement('mark');
            mark.className = 'fc';
            mark.setAttribute('data-cid', item.id);
            range.surroundContents(mark);
          }
          results.push({ id: item.id, found: true,
                         start: first ? first[0] : item.start,
                         end: lastBlock ? lastBlock[1] : item.start });
        }
        return results;
      };

      window.marginleafSetVisible = function (on) {
        document.documentElement.classList.toggle('nofc', !on);
      };

      window.marginleafFocus = function (id) {
        var m = document.querySelector('mark.fc[data-cid="' + id + '"]');
        if (!m) return null;
        m.scrollIntoView({ block: 'center' });
        return box(m.getBoundingClientRect());
      };

      // Whole-block comments live in a strip at the start of each block (its left edge, where the
      // bullet or the margin is). Only there does the block get outlined and the pointer turn into a
      // comment bubble; everywhere else the text behaves normally, so it can be selected for an
      // inline comment.
      var target = null, ZONE_L = 34, ZONE_R = 12;
      function blockAt(x, y) {
        var a = art();
        if (!a) return null;
        var list = a.querySelectorAll('li[data-sourcepos], :scope > [data-sourcepos]'), hit = null;
        for (var i = 0; i < list.length; i++) {
          var r = list[i].getBoundingClientRect();
          if (y >= r.top && y <= r.bottom && x >= r.left - ZONE_L && x <= r.left + ZONE_R) hit = list[i];
        }
        return hit;
      }
      function setTarget(el) {
        if (el === target) return;
        if (target) target.classList.remove('fc-hover');
        target = el;
        document.documentElement.classList.toggle('fc-zone', !!el);
        if (target) target.classList.add('fc-hover');
      }
      window.marginleafProbe = function (x, y) { setTarget(blockAt(x, y)); return !!target; };
      var pending = null;
      document.addEventListener('mousemove', function (e) {
        if (document.documentElement.classList.contains('nofc')) { setTarget(null); return; }
        if (e.buttons) { setTarget(null); return; }
        var x = e.clientX, y = e.clientY;
        if (pending) cancelAnimationFrame(pending);
        pending = requestAnimationFrame(function () { pending = null; setTarget(blockAt(x, y)); });
      });
      document.addEventListener('mouseleave', function () { setTarget(null); });

      document.addEventListener('click', function (e) {
        if (document.documentElement.classList.contains('nofc')) return;
        var s = window.getSelection();
        if (s && !s.isCollapsed) return;
        if (e.target.closest && e.target.closest('mark.fc, a, input, summary')) return;
        var el = blockAt(e.clientX, e.clientY);
        if (!el) return;
        var l = lines(el), b = box(el.getBoundingClientRect());
        b.type = 'add';
        b.text = squash(el.textContent);
        b.start = l ? l[0] : 1;
        b.end = l ? l[1] : b.start;
        window.webkit.messageHandlers.marginleaf.postMessage(b);
      });

      document.addEventListener('click', function (e) {
        var m = e.target.closest && e.target.closest('mark.fc');
        var s = window.getSelection();
        if (!m || (s && !s.isCollapsed) || document.documentElement.classList.contains('nofc')) return;
        var b = box(m.getBoundingClientRect());
        b.type = 'click';
        b.id = m.getAttribute('data-cid');
        window.webkit.messageHandlers.marginleaf.postMessage(b);
      });
    })();
    """
}
