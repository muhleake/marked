import Foundation

/// Status bar numbers.
struct TextCounts: Equatable, CustomStringConvertible {
    var words: Int
    var characters: Int
    var lines: Int

    init(words: Int, characters: Int, lines: Int) {
        self.words = words
        self.characters = characters
        self.lines = lines
    }

    init(_ text: String) {
        var words = 0
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        self.words = words
        characters = text.count
        lines = text.isEmpty ? 0 : text.utf8.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    var description: String {
        func plural(_ n: Int, _ word: String) -> String {
            "\(n.formatted()) \(word)\(n == 1 ? "" : "s")"
        }
        return [plural(words, "word"), plural(characters, "character"), plural(lines, "line")].joined(separator: " · ")
    }
}
