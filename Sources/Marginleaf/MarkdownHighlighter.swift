import AppKit
import MarginleafCore

/// Light Markdown colouring for the source view.
///
/// Up to `fullPassLimit` characters the whole text is recoloured shortly after
/// typing stops. Above it only the paragraph being edited is, so a huge file
/// never makes typing stutter.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    static let fullPassLimit = 300_000

    var baseSize: CGFloat = 13

    private var pending: DispatchWorkItem?

    private enum Kind { case heading, bold, italic, code, link, quote, listMarker, rule }

    private static func rule(_ pattern: String, _ kind: Kind, group: Int = 0) -> (NSRegularExpression, Kind, Int) {
        // The patterns are constants; a typo should fail loudly in CI, not silently skip colouring.
        let regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        return (regex, kind, group)
    }

    private static let rules: [(NSRegularExpression, Kind, Int)] = [
        rule(#"^#{1,6}[ \t].*$"#, .heading),
        rule(#"^[ \t]*>.*$"#, .quote),
        rule(#"^[ \t]*([-*+]|\d{1,9}[.)])[ \t]"#, .listMarker, group: 1),
        rule(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#, .rule),
        rule(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, .bold),
        rule(#"(?<![*\w])\*(?=\S)[^*\n]+?(?<=\S)\*(?![*\w])|(?<![_\w])_(?=\S)[^_\n]+?(?<=\S)_(?![_\w])"#, .italic),
        rule(#"`[^`\n]+`"#, .code),
        rule(#"!?\[[^\]\n]*\]\([^)\n]*\)"#, .link),
    ]

    // MARK: Fonts

    private var baseFont: NSFont { .monospacedSystemFont(ofSize: baseSize, weight: .regular) }

    private func font(_ weight: NSFont.Weight) -> NSFont {
        .monospacedSystemFont(ofSize: baseSize, weight: weight)
    }

    // MARK: Entry points

    /// Fenced-code ranges from the last full scan, kept in step with edits by `shiftFences`.
    private var fences: [NSRange] = []

    /// Colours the whole text (or, for a huge file, just applies the base style).
    func highlightAll(_ storage: NSTextStorage) {
        storage.beginEditing()
        fences = FenceScanner.fenceRanges(in: storage.string as NSString)
        if storage.length <= Self.fullPassLimit {
            apply(to: storage, in: NSRange(location: 0, length: storage.length))
        } else {
            storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        }
        storage.endEditing()
    }

    /// Typing recolours only the paragraph being edited, so a keystroke costs the same on any
    /// file size. A full pass runs later, and only when the edit could have changed which text
    /// is inside a code fence.
    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }

        let text = textStorage.string as NSString
        let paragraph = text.paragraphRange(for: editedRange)
        let touchesFence = fences.contains { NSIntersectionRange($0, NSRange(location: editedRange.location, length: max(1, editedRange.length))).length > 0 }
            || text.substring(with: paragraph).contains("```") || text.substring(with: paragraph).contains("~~~")
        shiftFences(editedRange: editedRange, delta: delta)
        apply(to: textStorage, in: paragraph)

        if touchesFence && textStorage.length <= Self.fullPassLimit {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self, weak textStorage] in
                guard let self, let textStorage else { return }
                self.highlightAll(textStorage)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    private func shiftFences(editedRange: NSRange, delta: Int) {
        guard delta != 0 else { return }
        let oldEnd = editedRange.location + editedRange.length - delta
        fences = fences.map { r in
            if r.location >= oldEnd { return NSRange(location: r.location + delta, length: r.length) }
            if NSMaxRange(r) > editedRange.location { return NSRange(location: r.location, length: max(0, r.length + delta)) }
            return r
        }
    }

    // MARK: Painting

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor]
    }

    /// Resets `target` to the base style, then paints each rule over it, skipping fenced code.
    /// The rules run on a copy of just this range, so the cost doesn't grow with the file.
    private func apply(to storage: NSTextStorage, in target: NSRange) {
        let whole = storage.string as NSString
        guard target.length > 0, NSMaxRange(target) <= whole.length else { return }

        storage.setAttributes(baseAttributes, range: target)

        for fence in fences {
            let part = NSIntersectionRange(fence, target)
            if part.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: part)
            }
        }

        let piece = whole.substring(with: target)
        let pieceRange = NSRange(location: 0, length: (piece as NSString).length)
        for (regex, kind, group) in Self.rules {
            regex.enumerateMatches(in: piece, options: [], range: pieceRange) { match, _, _ in
                guard let match else { return }
                let local = match.range(at: group)
                guard local.location != NSNotFound, local.length > 0 else { return }
                let range = NSRange(location: local.location + target.location, length: local.length)
                let full = NSRange(location: match.range.location + target.location, length: match.range.length)
                if self.fences.contains(where: { NSIntersectionRange($0, full).length > 0 }) { return }
                self.paint(kind, in: range, storage: storage)
            }
        }
    }

    private func paint(_ kind: Kind, in range: NSRange, storage: NSTextStorage) {
        switch kind {
        case .heading:
            storage.addAttributes([.font: font(.semibold), .foregroundColor: NSColor.systemBlue], range: range)
        case .bold:
            storage.addAttribute(.font, value: font(.bold), range: range)
        case .italic:
            storage.addAttribute(.obliqueness, value: 0.18, range: range)
        case .code:
            storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: range)
        case .link:
            storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
        case .quote:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
        case .rule:
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        }
    }
}
