import AppKit
import UniformTypeIdentifiers

final class MarkdownDocument: NSDocument {
    static let markdownType = "net.daringfireball.markdown"
    static let plainTextType = "public.plain-text"

    /// The document's text. The editor's NSTextView is attached to this storage,
    /// so reading (open, revert) updates every window automatically.
    let textStorage = NSTextStorage()

    private(set) var lineEnding: LineEnding = .lf
    private(set) var sourceEncoding: String.Encoding = .utf8

    var text: String { textStorage.string }

    /// True for `.txt` documents. Markdown types conform to plain text, so check the exact type.
    var isPlainText: Bool {
        guard let fileType, let type = UTType(fileType) else { return false }
        return !type.conforms(to: UTType(importedAs: Self.markdownType))
    }

    override init() {
        super.init()
        hasUndoManager = true
    }

    override class var autosavesInPlace: Bool { true }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override var fileType: String? {
        didSet {
            guard oldValue != fileType else { return }
            for controller in windowControllers {
                (controller as? DocumentWindowController)?.documentTypeDidChange()
            }
        }
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: - Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded: FileEncoding.Decoded
        do {
            decoded = try FileEncoding.decode(data)
        } catch {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError)
        }
        lineEnding = decoded.lineEnding
        sourceEncoding = decoded.encoding
        replaceText(with: decoded.text)
    }

    override func data(ofType typeName: String) throws -> Data {
        for controller in windowControllers {
            (controller as? DocumentWindowController)?.editorTextView?.breakUndoCoalescing()
        }
        return FileEncoding.encode(text, lineEnding: lineEnding)
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [Self.markdownType, Self.plainTextType]
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        typeName == Self.plainTextType ? "txt" : "md"
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.isExtensionHidden = false
        savePanel.allowsOtherFileTypes = false
        return true
    }

    /// Replaces the whole text without registering undo (used by open/revert).
    func replaceText(with newText: String) {
        let attributes = EditorStyle.baseAttributes()
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: newText)
        textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
    }
}
