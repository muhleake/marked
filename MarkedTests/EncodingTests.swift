import XCTest
@testable import Marked

final class EncodingTests: XCTestCase {
    func testUTF8() throws {
        let decoded = try FileEncoding.decode(Data("Héllo — wörld ✓\n".utf8))
        XCTAssertEqual(decoded.text, "Héllo — wörld ✓\n")
        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(decoded.lineEnding, .lf)
    }

    func testUTF8WithBOM() throws {
        let decoded = try FileEncoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("# Title".utf8))
        XCTAssertEqual(decoded.text, "# Title")
        XCTAssertEqual(decoded.encoding, .utf8)
    }

    func testUTF16LittleEndianWithBOM() throws {
        let data = Data([0xFF, 0xFE]) + "Ünïcode *text*".data(using: .utf16LittleEndian)!
        let decoded = try FileEncoding.decode(data)
        XCTAssertEqual(decoded.text, "Ünïcode *text*")
        XCTAssertEqual(decoded.encoding, .utf16LittleEndian)
    }

    func testUTF16BigEndianWithBOM() throws {
        let data = Data([0xFE, 0xFF]) + "big endian".data(using: .utf16BigEndian)!
        let decoded = try FileEncoding.decode(data)
        XCTAssertEqual(decoded.text, "big endian")
        XCTAssertEqual(decoded.encoding, .utf16BigEndian)
    }

    func testUTF16WithoutBOM() throws {
        let decoded = try FileEncoding.decode("- item one\n- item two\n".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(decoded.text, "- item one\n- item two\n")
        XCTAssertEqual(decoded.encoding, .utf16LittleEndian)
    }

    func testWindows1252() throws {
        // "café “quoted” – 50€" in Windows-1252: é=E9, “=93, ”=94, –=96, €=80. Invalid UTF-8.
        let bytes: [UInt8] = [0x63, 0x61, 0x66, 0xE9, 0x20, 0x93] + Array("quoted".utf8)
            + [0x94, 0x20, 0x96, 0x20, 0x35, 0x30, 0x80]
        let decoded = try FileEncoding.decode(Data(bytes))
        XCTAssertEqual(decoded.text, "café “quoted” – 50€")
        XCTAssertEqual(decoded.encoding, .windowsCP1252)
    }

    func testCRLFDetectedAndNormalized() throws {
        let decoded = try FileEncoding.decode(Data("a\r\nb\r\n\r\nc".utf8))
        XCTAssertEqual(decoded.text, "a\nb\n\nc")
        XCTAssertEqual(decoded.lineEnding, .crlf)
    }

    func testBareCRNormalizedToLF() throws {
        let decoded = try FileEncoding.decode(Data("a\rb\rc".utf8))
        XCTAssertEqual(decoded.text, "a\nb\nc")
        XCTAssertEqual(decoded.lineEnding, .lf)
    }

    func testMixedLineEndingsPickMajority() {
        XCTAssertEqual(FileEncoding.detectLineEnding("a\r\nb\r\nc\nd"), .crlf)
        XCTAssertEqual(FileEncoding.detectLineEnding("a\nb\nc\r\nd"), .lf)
        XCTAssertEqual(FileEncoding.detectLineEnding("no breaks"), .lf)
    }

    func testEncodeWritesUTF8WithoutBOM() {
        let data = FileEncoding.encode("é\n", lineEnding: .lf)
        XCTAssertEqual([UInt8](data), [0xC3, 0xA9, 0x0A])
    }

    func testEncodeRestoresCRLF() {
        let data = FileEncoding.encode("a\nb\n", lineEnding: .crlf)
        XCTAssertEqual(String(data: data, encoding: .utf8), "a\r\nb\r\n")
    }

    func testCRLFRoundTripIsByteIdentical() throws {
        let original = Data("# Head\r\n\r\n- one\r\n- two\r\n".utf8)
        let decoded = try FileEncoding.decode(original)
        XCTAssertEqual(FileEncoding.encode(decoded.text, lineEnding: decoded.lineEnding), original)
    }

    func testWindows1252SavesAsUTF8() throws {
        let decoded = try FileEncoding.decode(Data([0x63, 0x61, 0x66, 0xE9]))
        let saved = FileEncoding.encode(decoded.text, lineEnding: decoded.lineEnding)
        XCTAssertEqual(String(data: saved, encoding: .utf8), "café")
    }

    func testEmptyFile() throws {
        let decoded = try FileEncoding.decode(Data())
        XCTAssertEqual(decoded.text, "")
        XCTAssertEqual(decoded.lineEnding, .lf)
    }
}
