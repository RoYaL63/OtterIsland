import AppKit
import SwiftUI

/// Un raccourci épinglé dans l'onglet Raccourcis de l'île.
struct QuickShortcut: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        /// Une app (.app), ouverte ou ramenée au premier plan.
        case app
        /// Un dossier ou un fichier, ouvert avec l'app par défaut.
        case file
        /// Une adresse web (ou tout lien : mailto:, slack://…).
        case link
        /// Un raccourci de l'app Raccourcis de macOS, exécuté.
        case shortcut
    }

    var id = UUID()
    var kind: Kind
    var title: String
    /// Chemin (app, fichier), adresse (lien) ou nom (raccourci macOS).
    var target: String

    /// Lance le raccourci.
    func open() {
        switch kind {
        case .app:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target), configuration: NSWorkspace.OpenConfiguration())
        case .file:
            NSWorkspace.shared.open(URL(fileURLWithPath: target))
        case .link:
            if let url = URL(string: target) { NSWorkspace.shared.open(url) }
        case .shortcut:
            FocusMode.trigger(target)
        }
    }

    /// N'existe plus (app désinstallée, dossier déplacé) : affiché grisé.
    var isMissing: Bool {
        switch kind {
        case .app, .file: return !FileManager.default.fileExists(atPath: target)
        case .link: return URL(string: target) == nil
        case .shortcut: return false
        }
    }

    /// Icône du Finder pour une app ou un fichier ; nil pour les autres.
    var fileIcon: NSImage? {
        guard kind == .app || kind == .file, !isMissing else { return nil }
        return NSWorkspace.shared.icon(forFile: target)
    }

    /// Symbole pour ce qui n'a pas d'icône de fichier.
    var symbol: String {
        switch kind {
        case .app: return "app.dashed"
        case .file: return "folder"
        case .link: return "link"
        case .shortcut: return "square.2.layers.3d.fill"
        }
    }

    var kindLabel: String {
        switch kind {
        case .app: return "App"
        case .file: return "Dossier ou fichier"
        case .link: return "Lien"
        case .shortcut: return "Raccourci macOS"
        }
    }

    // MARK: Fabriques

    static func app(at url: URL) -> QuickShortcut {
        QuickShortcut(kind: .app, title: FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: ""), target: url.path)
    }

    static func file(at url: URL) -> QuickShortcut {
        QuickShortcut(kind: .file, title: FileManager.default.displayName(atPath: url.path), target: url.path)
    }

    /// Accepte « exemple.fr » sans schéma : on ajoute https://.
    static func link(title: String, address: String) -> QuickShortcut? {
        var text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") && !text.hasPrefix("mailto:") { text = "https://" + text }
        guard let url = URL(string: text), url.scheme != nil else { return nil }
        let name = title.trimmingCharacters(in: .whitespaces)
        return QuickShortcut(kind: .link, title: name.isEmpty ? (url.host ?? text) : name, target: text)
    }
}

/// Liste des raccourcis, persistée en JSON dans les préférences.
@MainActor
final class QuickShortcutStore: ObservableObject {
    static let shared = QuickShortcutStore()

    @Published var items: [QuickShortcut] { didSet { save() } }

    private let key = "quickShortcuts"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([QuickShortcut].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func add(_ item: QuickShortcut) {
        // Pas deux fois la même cible.
        guard !items.contains(where: { $0.kind == item.kind && $0.target == item.target }) else { return }
        items.append(item)
    }

    func remove(_ item: QuickShortcut) {
        items.removeAll { $0.id == item.id }
    }

    func move(_ item: QuickShortcut, by offset: Int) {
        guard let index = items.firstIndex(of: item) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
