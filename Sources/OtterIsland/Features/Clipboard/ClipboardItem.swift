import Foundation

/// Une entrée de l'historique du presse-papier.
struct ClipboardItem: Identifiable, Equatable, Codable {
    enum Content: Equatable, Codable {
        case text(String)
        case image(Data) // PNG
    }

    var id = UUID()
    let content: Content
    var date = Date()

    /// Deux entrées sont « les mêmes » si leur contenu est identique (pour la déduplication).
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.content == rhs.content
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    var text: String? {
        if case .text(let value) = content { return value }
        return nil
    }

    var imageData: Data? {
        if case .image(let data) = content { return data }
        return nil
    }
}
