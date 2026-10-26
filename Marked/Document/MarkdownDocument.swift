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

    // MARK: - Print and Export as PDF (the rendered preview, not raw text)

    /// Markdown rendering applies unless this is a plain .txt window not treated as Markdown.
    var printsAsMarkdown: Bool {
        guard isPlainText else { return true }
        return windowControllers.contains { ($0 as? DocumentWindowController)?.treatsAsMarkdown == true }
    }

    override func printDocument(_ sender: Any?) {
        PreviewPrinter.makePrintOperation(for: self, markdown: printsAsMarkdown, printInfo: printInfo) { [weak self] operation in
            guard let self, let operation else { NSSound.beep(); return }
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            self.runModalPrintOperation(operation, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    /// File ▸ Export as PDF…
    override func saveToPDF(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = ((displayName as NSString).deletingPathExtension) + ".pdf"
        if let folder = fileURL?.deletingLastPathComponent() { panel.directoryURL = folder }
        let save: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.exportPDF(to: url) { error in
                if let error { self.presentError(error) }
            }
        }
        if let window = windowControllers.first?.window {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            save(panel.runModal())
        }
    }

    /// Writes the rendered, paginated document to `url` as PDF.
    func exportPDF(to url: URL, completion: @escaping (Error?) -> Void) {
        let info = printInfo.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        PreviewPrinter.makePrintOperation(for: self, markdown: printsAsMarkdown, printInfo: info) { operation in
            guard let operation else { completion(CocoaError(.fileWriteUnknown)); return }
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            if let window = self.windowControllers.first?.window {
                operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                // runModal(for:) returns before the job finishes; wait for the file.
                Self.waitForFile(url, completion: completion)
            } else {
                completion(operation.run() ? nil : CocoaError(.fileWriteUnknown))
            }
        }
    }

    private static func waitForFile(_ url: URL, attempts: Int = 100, completion: @escaping (Error?) -> Void) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > 0 { completion(nil); return }
        guard attempts > 0 else { completion(CocoaError(.fileWriteUnknown)); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForFile(url, attempts: attempts - 1, completion: completion)
        }
    }

    // MARK: - Changes made by other apps

    private var isAskingToReload = false

    /// How to ask about reloading; tests replace it. Calls back with true to reload.
    var askToReload: (MarkdownDocument, @escaping (Bool) -> Void) -> Void = { document, answer in
        let alert = NSAlert()
        alert.messageText = "“\(document.displayName)” was changed by another application."
        alert.informativeText = document.isDocumentEdited
            ? "Reloading shows the version on disk and discards the changes you made here."
            : "Do you want to reload it to see the latest version?"
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep This Version")
        if let window = document.windowControllers.first?.window {
            alert.beginSheetModal(for: window) { answer($0 == .alertFirstButtonReturn) }
        } else {
            answer(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    /// NSFilePresenter: the file changed on disk (called on a background queue).
    override func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in self?.checkForExternalChange() }
    }

    /// Prompts to reload if the file on disk no longer matches what this document
    /// last read or saved. Also run when Marked becomes active.
    func checkForExternalChange() {
        guard !isAskingToReload, let url = fileURL, let type = fileType,
              let diskDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return }
        if let known = fileModificationDate, abs(diskDate.timeIntervalSince(known)) < 0.001 { return }
        guard let data = try? Data(contentsOf: url), let decoded = try? FileEncoding.decode(data) else { return }
        if decoded.text == text {
            // Same contents (e.g. touched or re-saved identically): nothing to ask.
            fileModificationDate = diskDate
            return
        }
        isAskingToReload = true
        askToReload(self) { [weak self] reload in
            guard let self else { return }
            self.isAskingToReload = false
            if reload {
                do { try self.revert(toContentsOf: url, ofType: type) } catch { self.presentError(error) }
            } else {
                // Keep this version; a later save overwrites the file without another warning.
                self.fileModificationDate = diskDate
            }
        }
    }
}
