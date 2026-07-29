import Foundation

/// Une entrée de l'historique du presse-papier.
struct ClipboardItem: Identifiable, Equatable, Codable {
    enum Content: Equatable, Codable {
        case text(String)
        case image(Data) // PNG
        /// Chemin d'un fichier image sur disque (capture d'écran). On stocke la
        /// référence et pas les octets : l'historique JSON resterait sinon à
        /// plusieurs dizaines de Mo avec 30 captures Retina en base64.
        case file(String)
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

    var fileURL: URL? {
        if case .file(let path) = content { return URL(fileURLWithPath: path) }
        return nil
    }
}
