import Foundation

public struct DecodedText: Equatable {
    public var text: String
    public var usesCRLF: Bool
    public var hasBOM: Bool

    public init(text: String, usesCRLF: Bool, hasBOM: Bool) {
        self.text = text
        self.usesCRLF = usesCRLF
        self.hasBOM = hasBOM
    }
}

/// Reads and writes a note's bytes without changing anything the user didn't edit.
///
/// The editor works in LF internally. We remember whether the file used CRLF or
/// started with a UTF-8 BOM and put both back on save, so opening a file and
/// saving it unchanged gives back the same bytes.
///
/// Files that aren't valid UTF-8 are refused (`decode` returns nil). Guessing
/// another encoding would silently rewrite the file's bytes on the next save.
public enum TextCodec {
    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    public static func decode(_ data: Data) -> DecodedText? {
        var body = data
        var hasBOM = false
        if data.starts(with: bom) {
            hasBOM = true
            body = data.dropFirst(bom.count)
        }
        guard let raw = String(data: body, encoding: .utf8) else { return nil }
        let usesCRLF = raw.contains("\r\n")
        let text = usesCRLF ? raw.replacingOccurrences(of: "\r\n", with: "\n") : raw
        return DecodedText(text: text, usesCRLF: usesCRLF, hasBOM: hasBOM)
    }

    public static func encode(_ text: String, usesCRLF: Bool, hasBOM: Bool) -> Data {
        let out = usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
        var data = Data()
        if hasBOM { data.append(contentsOf: bom) }
        data.append(contentsOf: out.utf8)
        return data
    }
}
