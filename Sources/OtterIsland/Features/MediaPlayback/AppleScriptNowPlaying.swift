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
            let info = Self.runScript()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Ne republie que sur vrai changement, sinon la minuterie de
                // sommeil de la loutre se relancerait à chaque sondage.
                if self.current != info { self.current = info }
                self.updateArtwork(for: info)
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

    /// Champs renvoyés : playing|titre|artiste|position(s)|durée(s)|urlPochette
    /// Ne réveille pas les apps : on vérifie d'abord qu'elles tournent via System Events.
    private static let stateScript = """
    set out to "stopped"
    tell application "System Events"
        set running to name of every process
    end tell
    if running contains "Spotify" then
        tell application "Spotify"
            if player state is playing then
                set d to (duration of current track) / 1000
                set out to "playing|" & (name of current track) & "|" & (artist of current track) & "|" & (player position) & "|" & d & "|" & (artwork url of current track)
            end if
        end tell
    end if
    if out starts with "stopped" and running contains "Music" then
        tell application "Music"
            if player state is playing then
                set out to "playing|" & (name of current track) & "|" & (artist of current track) & "|" & (player position) & "|" & (duration of current track) & "|"
            end if
        end tell
    end if
    return out
    """

    private static func runScript() -> NowPlayingInfo? {
        guard let output = runOsascript(stateScript) else { return nil }
        let parts = output.components(separatedBy: "|")
        guard parts.count >= 3, parts[0] == "playing" else { return nil }

        func number(_ index: Int) -> Double {
            guard parts.count > index else { return 0 }
            return Double(parts[index].replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        let artwork = parts.count > 5 && !parts[5].isEmpty ? parts[5] : nil

        return NowPlayingInfo(
            title: parts[1],
            artist: parts[2],
            isPlaying: true,
            duration: number(4),
            position: number(3),
            sampledAt: Date(),
            artworkURL: artwork
        )
    }

    private static func control(_ command: String) {
        let script = """
        tell application "System Events"
            set running to name of every process
        end tell
        if running contains "Spotify" then
            tell application "Spotify" to \(command)
        else if running contains "Music" then
            tell application "Music" to \(command)
        end if
        """
        _ = runOsascript(script)
    }

    private static func runOsascript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
