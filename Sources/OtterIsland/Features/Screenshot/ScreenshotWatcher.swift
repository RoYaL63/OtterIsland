import AppKit

/// Surveille le dossier de captures d'écran (celui configuré pour `screencapture`,
/// `~/Desktop` par défaut) et publie chaque nouvelle capture pour affichage
/// transitoire dans l'encoche. Même technique que `ClaudeCodeInbox` : un
/// `DispatchSourceFileSystemObject` sur le descripteur du dossier.
@MainActor
final class ScreenshotWatcher: ObservableObject {
    struct Shot: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let image: NSImage

        static func == (lhs: Shot, rhs: Shot) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var latest: Shot?
    /// Historique persistant des captures, le plus récent en premier — alimente
    /// l'onglet "Captures" au lieu du seul aperçu transitoire de `latest`.
    @Published private(set) var history: [URL] = []

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var directoryHandle: CInt = -1
    private var seenPaths: Set<String> = []
    private let fileName = "screenshots.json"

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]

    init() {
        directory = Self.screenshotDirectory()
        let paths = Persistence.load([String].self, from: fileName) ?? []
        history = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func start() {
        // Écarte ce qui existe déjà dans le dossier : seules les captures prises
        // après le lancement doivent déclencher un aperçu / entrer dans l'historique.
        seenPaths = Set(currentImageFiles().map(\.path)).union(history.map(\.path))
        watch()
    }

    private static func screenshotDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: expanded.path) {
                return expanded
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func currentImageFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    private func watch() {
        directoryHandle = open(directory.path, O_EVTONLY)
        guard directoryHandle >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryHandle,
            eventMask: [.write, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.scan()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.directoryHandle, fd >= 0 { close(fd) }
        }
        src.resume()
        source = src
    }

    private func scan() {
        for file in currentImageFiles() where !seenPaths.contains(file.path) {
            seenPaths.insert(file.path)
            // macOS écrit la capture en une ou deux passes rapides : petite marge
            // avant lecture pour ne pas charger un fichier encore tronqué.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.load(file)
            }
        }
    }

    private func load(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else { return }
        latest = Shot(url: url, image: image)
        history.insert(url, at: 0)
        persist()
    }

    func clear() {
        latest = nil
    }

    func remove(_ url: URL) {
        history.removeAll { $0 == url }
        persist()
    }

    func clearHistory() {
        history.removeAll()
        persist()
    }

    private func persist() {
        Persistence.save(history.map(\.path), to: fileName)
    }

    deinit {
        source?.cancel()
    }
}
