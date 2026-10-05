import Foundation
import Combine

/// Surveille ~/.otterisland/inbox pour de nouvelles demandes d'action Claude Code
/// et écrit les réponses dans ~/.otterisland/outbox. Une demande à la fois dans l'encoche.
@MainActor
final class ClaudeCodeInbox: ObservableObject {
    @Published private(set) var pending: ActionRequest?
    /// Fichier de la demande affichée, pour la retirer sans dépendre de son id.
    private var pendingFile: URL?

    /// Émis à chaque décision (true = approuvé) pour que la loutre réagisse.
    let decisions = PassthroughSubject<Bool, Never>()

    private let root: URL
    private let inboxURL: URL
    private let outboxURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var directoryHandle: CInt = -1

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        root = home.appendingPathComponent(".otterisland", isDirectory: true)
        inboxURL = root.appendingPathComponent("inbox", isDirectory: true)
        outboxURL = root.appendingPathComponent("outbox", isDirectory: true)
    }

    private var isRunning = false

    /// Idempotent : on peut l'appeler à chaque activation d'un assistant.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        createDirectoriesIfNeeded()
        scan() // récupère ce qui est déjà là au démarrage
        watch()
    }

    private func createDirectoriesIfNeeded() {
        for url in [root, inboxURL, outboxURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func watch() {
        directoryHandle = open(inboxURL.path, O_EVTONLY)
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

    /// Prend le plus ancien fichier .json de l'inbox et le présente.
    private func scan() {
        guard pending == nil else { return } // une demande à la fois
        let files = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []

        let requests = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in requests {
            guard let data = try? Data(contentsOf: file) else { continue }
            let request = (try? JSONDecoder.iso.decode(ActionRequest.self, from: data))
                ?? ActionRequest.fromAssistantMessage(data, id: file.deletingPathExtension().lastPathComponent)
            guard let request else { continue }
            // Notification d'assistant restée là pendant une absence : passée
            // une heure, elle ne veut plus rien dire.
            if request.isNotice, let date = Self.modificationDate(file), Date().timeIntervalSince(date) > 3600 {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            pending = request
            pendingFile = file
            break
        }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Notification lue : on la retire, sans réponse à écrire.
    func dismiss(_ request: ActionRequest) {
        if let pendingFile { try? FileManager.default.removeItem(at: pendingFile) }
        pending = nil
        pendingFile = nil
        scan()
    }

    /// Écrit la réponse, supprime la demande de l'inbox, libère l'encoche.
    func resolve(_ request: ActionRequest, approved: Bool) {
        let response = ActionResponse(id: request.id, approved: approved)
        let out = outboxURL.appendingPathComponent("\(request.id).json")
        if let data = try? JSONEncoder.iso.encode(response) {
            try? data.write(to: out)
        }
        // Retire le fichier de demande correspondant.
        let files = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let decoded = try? JSONDecoder.iso.decode(ActionRequest.self, from: data),
               decoded.id == request.id {
                try? FileManager.default.removeItem(at: file)
            }
        }
        pending = nil
        pendingFile = nil
        decisions.send(approved)
        scan() // enchaîne sur la suivante s'il y en a
    }

    deinit {
        source?.cancel()
    }
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()
}
