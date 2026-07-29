import Foundation
import AppKit
import Combine

/// Détecte la lecture en cours dans Spotify ou Apple Music via AppleScript,
/// sans framework privé. Sonde toutes les 3 s sur une file de fond.
///
/// macOS demandera l'autorisation « Automatisation » au premier appel : c'est
/// attendu et sans danger, on ne fait que lire l'état du lecteur.
@MainActor
final class AppleScriptNowPlaying: NowPlayingProvider, ObservableObject {
    @Published private(set) var current: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    /// true si macOS a refusé l'Automatisation vers Spotify/Music/System Events :
    /// sans ça, le script échoue en silence et rien ne semble jamais jouer.
    @Published private(set) var automationDenied = false

    private var timer: Timer?
    private var lastArtworkKey: String?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async {
            let result = Self.runScript()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Ne republie que sur vrai changement, sinon la minuterie de
                // sommeil de la loutre se relancerait à chaque sondage.
                if self.current != result.info { self.current = result.info }
                self.automationDenied = result.automationDenied
                self.updateArtwork(for: result.info)
            }
        }
    }

    /// Télécharge la pochette quand le morceau change ; l'efface quand rien ne joue.
    private func updateArtwork(for info: NowPlayingInfo?) {
        guard let info else {
            lastArtworkKey = nil
            artwork = nil
            return
        }
        guard info.trackKey != lastArtworkKey else { return }
        lastArtworkKey = info.trackKey

        guard let urlString = info.artworkURL, let url = URL(string: urlString) else {
            artwork = nil
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async {
                // Ignore si le morceau a encore changé entre-temps.
                guard self?.lastArtworkKey == info.trackKey else { return }
                self?.artwork = image
            }
        }.resume()
    }

    // MARK: Contrôles (Milestone 2)

    func togglePlayPause() { Self.control("playpause") }
    func nextTrack() { Self.control("next track") }
    func previousTrack() { Self.control("previous track") }

    // MARK: AppleScript

    /// Champs renvoyés : (playing|paused)|titre|artiste|position(s)|durée(s)|urlPochette
    ///
    /// `application "X" is running` est un prédicat AppleScript pur (LaunchServices) :
    /// il ne réveille pas l'app et surtout n'envoie aucun Apple Event, donc ne demande
    /// aucune permission. On évitait ça via "System Events", qui demande sa PROPRE
    /// autorisation Automatisation distincte de celle de Spotify/Music — un maillon en
    /// plus qui pouvait échouer tout seul et faire planter tout le relevé en silence.
    /// `artwork url` est aussi try-protégée : certaines pistes ne l'exposent pas.
    ///
    /// Important : comparer `player state` doit se faire directement (`if player state
    /// is playing`), jamais après l'avoir stocké dans une variable — `set st to player
    /// state` puis `if st is playing` casse le parseur AppleScript (les constantes
    /// playing/paused ne sont résolues qu'en comparaison directe de la propriété).
    private static let stateScript = """
    set out to "stopped"
    if application "Spotify" is running then
        try
            tell application "Spotify"
                set stateWord to "stopped"
                if player state is playing then
                    set stateWord to "playing"
                else if player state is paused then
                    set stateWord to "paused"
                end if
                if stateWord is not "stopped" then
                    set d to (duration of current track) / 1000
                    set artUrl to ""
                    try
                        set artUrl to artwork url of current track
                    end try
                    set out to stateWord & "|" & (name of current track) & "|" & (artist of current track) & "|" & (player position) & "|" & d & "|" & artUrl
                end if
            end tell
        on error errMsg number errNum
            set out to "error|" & errNum & "|" & errMsg
        end try
    end if
    if out is "stopped" and application "Music" is running then
        try
            tell application "Music"
                set stateWord to "stopped"
                if player state is playing then
                    set stateWord to "playing"
                else if player state is paused then
                    set stateWord to "paused"
                end if
                if stateWord is not "stopped" then
                    set out to stateWord & "|" & (name of current track) & "|" & (artist of current track) & "|" & (player position) & "|" & (duration of current track) & "|"
                end if
            end tell
        on error errMsg number errNum
            set out to "error|" & errNum & "|" & errMsg
        end try
    end if
    return out
    """

    private static func runScript() -> (info: NowPlayingInfo?, automationDenied: Bool) {
        let result = runOsascript(stateScript)
        if result.automationDenied { return (nil, true) }
        guard let output = result.output else { return (nil, false) }
        let parts = output.components(separatedBy: "|")
        // Une erreur AppleScript côté Spotify/Music (le "try" l'a capturée) : le plus
        // souvent une Automatisation non accordée pour l'app elle-même.
        if parts[0] == "error" { return (nil, true) }
        guard parts.count >= 3, parts[0] == "playing" || parts[0] == "paused" else { return (nil, false) }

        func number(_ index: Int) -> Double {
            guard parts.count > index else { return 0 }
            return Double(parts[index].replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        let artwork = parts.count > 5 && !parts[5].isEmpty ? parts[5] : nil

        return (NowPlayingInfo(
            title: parts[1],
            artist: parts[2],
            isPlaying: parts[0] == "playing",
            duration: number(4),
            position: number(3),
            sampledAt: Date(),
            artworkURL: artwork
        ), false)
    }

    private static func control(_ command: String) {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to \(command)
        else if application "Music" is running then
            tell application "Music" to \(command)
        end if
        """
        _ = runOsascript(script)
    }

    private static func runOsascript(_ script: String) -> (output: String?, automationDenied: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (nil, false)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errorText = String(data: errData, encoding: .utf8) ?? ""
        // -1743 = errAEEventNotPermitted : Automatisation refusée pour cette app.
        // Le message est localisé selon la langue système, le code numérique ne l'est pas.
        let denied = errorText.contains("-1743")
        return (output, denied)
    }
}
