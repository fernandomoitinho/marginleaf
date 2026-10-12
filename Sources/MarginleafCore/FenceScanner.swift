import Foundation

/// Finds fenced code blocks (``` or ~~~) so the source view can leave their
/// contents uncoloured by the inline rules. A plain line scan, no regex, so it
/// stays fast on large files.
public enum FenceScanner {
    /// Ranges (in UTF-16 units) covering each fence from its opening line
    /// through its closing line. An unclosed fence runs to the end of the text.
    public static func fenceRanges(in string: String) -> [NSRange] {
        fenceRanges(in: string as NSString)
    }

    public static func fenceRanges(in text: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var open: (start: Int, marker: UInt16, count: Int)?
        var location = 0

        while location < text.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                              for: NSRange(location: location, length: 0))

            // Up to three spaces of indent, then a run of 3+ backticks or tildes.
            var i = lineStart
            var indent = 0
            while i < contentsEnd, text.character(at: i) == 0x20, indent < 4 {
                i += 1
                indent += 1
            }
            var marker: UInt16 = 0
            var run = 0
            if indent < 4, i < contentsEnd {
                let c = text.character(at: i)
                if c == 0x60 || c == 0x7E { // ` or ~
                    marker = c
                    var j = i
                    while j < contentsEnd, text.character(at: j) == c { j += 1 }
                    run = j - i
                }
            }
            let isFence = run >= 3

            if let o = open {
                if isFence, marker == o.marker, run >= o.count {
                    result.append(NSRange(location: o.start, length: lineEnd - o.start))
                    open = nil
                }
            } else if isFence {
                open = (lineStart, marker, run)
            }

            location = lineEnd
        }

        if let o = open {
            result.append(NSRange(location: o.start, length: text.length - o.start))
        }
        return result
    }
}
