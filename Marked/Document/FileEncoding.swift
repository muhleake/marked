import Foundation

/// Line-ending style of a file on disk. Text is held in memory with LF only.
enum LineEnding: Equatable {
    case lf
    case crlf

    var string: String { self == .crlf ? "\r\n" : "\n" }
}

/// Reads text files in whatever encoding they arrive in and writes UTF-8,
/// preserving the original line endings.
enum FileEncoding {
    struct Decoded: Equatable {
        /// Normalized text: every line break is "\n".
        var text: String
        var encoding: String.Encoding
        var lineEnding: LineEnding
    }

    enum DecodeError: Error {
        case undecodable
    }

    static func decode(_ data: Data) throws -> Decoded {
        let (raw, encoding) = try decodeString(data)
        let lineEnding = detectLineEnding(raw)
        return Decoded(text: normalizeLineEndings(raw), encoding: encoding, lineEnding: lineEnding)
    }

    /// Always UTF-8 (no BOM), with `\n` expanded to the requested line ending.
    static func encode(_ text: String, lineEnding: LineEnding) -> Data {
        let normalized = normalizeLineEndings(text)
        let out = lineEnding == .crlf ? (normalized as NSString).replacingOccurrences(of: "\n", with: "\r\n") : normalized
        return Data(out.utf8)
    }

    // MARK: - Encoding detection

    static func decodeString(_ data: Data) throws -> (String, String.Encoding) {
        let bytes = [UInt8](data.prefix(4))

        // Byte-order marks first.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            if let s = String(data: data.dropFirst(3), encoding: .utf8) { return (s, .utf8) }
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            if let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return (s, .utf16LittleEndian) }
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return (s, .utf16BigEndian) }
        }

        // UTF-16 without a BOM: lots of NUL bytes on one side of each pair.
        if let utf16 = guessBOMlessUTF16(data), let s = String(data: data, encoding: utf16) {
            return (s, utf16)
        }

        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
        if let s = String(data: data, encoding: .windowsCP1252) { return (s, .windowsCP1252) }
        // Latin-1 maps every byte, so this only fails on impossible input.
        if let s = String(data: data, encoding: .isoLatin1) { return (s, .isoLatin1) }
        throw DecodeError.undecodable
    }

    private static func guessBOMlessUTF16(_ data: Data) -> String.Encoding? {
        guard data.count >= 4, data.count % 2 == 0 else { return nil }
        let sample = data.prefix(4096)
        var evenZeros = 0, oddZeros = 0
        for (i, byte) in sample.enumerated() where byte == 0 {
            if i % 2 == 0 { evenZeros += 1 } else { oddZeros += 1 }
        }
        let pairs = sample.count / 2
        if oddZeros > pairs * 4 / 10 && evenZeros == 0 { return .utf16LittleEndian }
        if evenZeros > pairs * 4 / 10 && oddZeros == 0 { return .utf16BigEndian }
        return nil
    }

    // MARK: - Line endings

    /// CRLF if CRLF pairs outnumber bare LFs; otherwise LF.
    static func detectLineEnding(_ text: String) -> LineEnding {
        var crlf = 0, lf = 0
        var previousWasCR = false
        for unit in text.utf8 {
            if unit == 0x0A {
                if previousWasCR { crlf += 1 } else { lf += 1 }
            }
            previousWasCR = unit == 0x0D
        }
        return crlf > lf ? .crlf : .lf
    }

    /// Converts CRLF and bare CR to LF.
    static func normalizeLineEndings(_ text: String) -> String {
        // Check bytes: Swift treats "\r\n" as one Character, so contains("\r") misses it.
        guard text.utf8.contains(0x0D) else { return text }
        return (text as NSString)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
