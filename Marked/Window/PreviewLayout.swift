import Foundation

enum PreviewLayout: String, CaseIterable {
    case split
    case editorOnly
    case previewOnly

    var title: String {
        switch self {
        case .split: "Split"
        case .editorOnly: "Editor Only"
        case .previewOnly: "Preview Only"
        }
    }

    var next: PreviewLayout {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
