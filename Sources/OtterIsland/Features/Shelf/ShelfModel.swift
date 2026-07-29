import AppKit
import Combine

/// Étagère : fichiers déposés temporairement, prêts à glisser ailleurs ou à envoyer en AirDrop.
@MainActor
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let fileName = "shelf.json"

    init() {
        // Recharge les fichiers déposés, en écartant ceux qui n'existent plus.
        let paths = Persistence.load([String].self, from: fileName) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
        }
        persist()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        persist()
    }

    /// Charge les fichiers d'un glisser-déposer (item providers). Partagé entre
    /// l'étagère elle-même et la détection de survol sur l'encoche repliée.
    @discardableResult
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var found = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            found = true
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                Task { @MainActor in self?.add([url]) }
            }
        }
        return found
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        Persistence.save(items.map(\.path), to: fileName)
    }

    /// Ouvre la feuille de partage AirDrop pour tous les fichiers de l'étagère.
    func airDropAll(from view: NSView?) {
        guard !items.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: items)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
