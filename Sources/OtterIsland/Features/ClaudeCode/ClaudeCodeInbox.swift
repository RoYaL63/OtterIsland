import Foundation
import Combine

/// Surveille ~/.otterisland/inbox pour les demandes et notifications des
/// assistants (Claude Code, Codex, tes propres scripts) et écrit les réponses
/// dans ~/.otterisland/outbox.
///
/// Les demandes forment une LISTE : elles s'affichent dans l'onglet Assistants IA
/// et ne bloquent jamais le reste de l'île. Chacune peut être ignorée, ce qui
/// la retire sans écrire de réponse.
@MainActor
final class ClaudeCodeInbox: ObservableObject {
    /// Demandes en attente, de la plus ancienne à la plus récente.
    @Published private(set) var requests: [ActionRequest] = []

    /// La plus ancienne : c'est elle qui rend la loutre curieuse et allume le
    /// point d'attente de l'île repliée.
    var pending: ActionRequest? { requests.first }

    /// Émis à chaque décision (true = approuvé) pour que la loutre réagisse.
    let decisions = PassthroughSubject<Bool, Never>()

    /// Une demande plus vieille que ça n'attend plus personne : elle est retirée
    /// toute seule (le script qui l'a déposée a abandonné depuis longtemps).
    static let maxAge: TimeInterval = 3600
    /// Au-delà, on la signale comme probablement périmée (le script d'exemple
    /// attend 120 s au plus).
    static let staleAge: TimeInterval = 300

    private let root: URL
    private let inboxURL: URL
    private let outboxURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var directoryHandle: CInt = -1
    private var expiryTimer: Timer?
    /// Fichier de chaque demande, par identifiant : on retire le bon fichier
    /// sans avoir à tout relire (l'identifiant d'un message relayé vient de
    /// son nom de fichier).
    private var files: [String: URL] = [:]

    /// `root` : dossier de travail, `~/.otterisland` par défaut (injectable pour les tests).
    init(root: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.root = root ?? home.appendingPathComponent(".otterisland", isDirectory: true)
        inboxURL = self.root.appendingPathComponent("inbox", isDirectory: true)
        outboxURL = self.root.appendingPathComponent("outbox", isDirectory: true)
    }

    private var isRunning = false

    /// Idempotent : on peut l'appeler à chaque activation d'un assistant.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        createDirectoriesIfNeeded()
        scan() // récupère ce qui est déjà là au démarrage
        watch()
        // Une demande vieillit sans qu'aucun fichier ne change : on relit
        // régulièrement pour retirer celles qui ont expiré.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
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

    /// Relit tout l'inbox. Une demande sans date prend celle de son fichier :
    /// sans ça, l'âge d'un message relayé repartirait de zéro à chaque relevé.
    private func scan() {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        var found: [ActionRequest] = []
        var fileForID: [String: URL] = [:]
        for file in entries.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file) else { continue }
            let modified = Self.modificationDate(file)
            guard let decoded = (try? JSONDecoder.iso.decode(ActionRequest.self, from: data))
                ?? ActionRequest.fromAssistantMessage(data, id: file.deletingPathExtension().lastPathComponent)
            else { continue }
            let created = decoded.createdAt ?? modified
            // Périmée : plus personne n'attend. On la retire du disque.
            if let created, Date().timeIntervalSince(created) > Self.maxAge {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            let current = ActionRequest(id: decoded.id, title: decoded.title, detail: decoded.detail, kind: decoded.kind, createdAt: created)
            found.append(current)
            fileForID[current.id] = file
        }
        files = fileForID
        if found != requests { requests = found }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Retire une demande de la liste et du disque.
    private func remove(_ request: ActionRequest) {
        if let file = files[request.id] { try? FileManager.default.removeItem(at: file) }
        files[request.id] = nil
        requests.removeAll { $0.id == request.id }
    }

    /// Ignorer : la demande disparaît, sans réponse écrite. Si un script
    /// l'attend encore, il arrivera à son propre délai.
    func dismiss(_ request: ActionRequest) {
        remove(request)
    }

    func dismissAll() {
        for request in requests { remove(request) }
    }

    /// Écrit la réponse, retire la demande de l'inbox.
    func resolve(_ request: ActionRequest, approved: Bool) {
        let response = ActionResponse(id: request.id, approved: approved)
        let out = outboxURL.appendingPathComponent("\(request.id).json")
        if let data = try? JSONEncoder.iso.encode(response) {
            try? data.write(to: out)
        }
        remove(request)
        decisions.send(approved)
    }

    deinit {
        source?.cancel()
        expiryTimer?.invalidate()
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
