import Foundation

/// Infos de lecture en cours.
struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool
    let duration: Double    // secondes
    let position: Double    // secondes, au moment de l'échantillon
    let sampledAt: Date
    let artworkURL: String?

    /// Position lue, interpolée depuis l'échantillon si la lecture continue.
    func position(at date: Date) -> Double {
        let pos = isPlaying ? position + date.timeIntervalSince(sampledAt) : position
        return min(max(0, pos), duration)
    }

    /// Fraction 0...1 pour la barre de progression.
    func fraction(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return position(at: date) / duration
    }

    /// Deux morceaux sont « le même » si titre + artiste identiques (pour la pochette).
    var trackKey: String { "\(title)—\(artist)" }
}

/// Interface média. Une implémentation ScriptingBridge (Music/Spotify) et une
/// implémentation MediaRemote viendront au Milestone 2 ; le framework privé
/// MediaRemote est restreint depuis macOS 15.4, d'où l'abstraction.
/// @MainActor : consommée uniquement par l'UI, et les implémentations publient
/// via @Published — isoler le protocole évite les conformances trans-acteur
/// (erreur en mode langage Swift 6).
@MainActor
protocol NowPlayingProvider: AnyObject {
    var current: NowPlayingInfo? { get }
    func start()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
}

/// Implémentation vide en attendant. Permet de câbler l'UI dès maintenant.
@MainActor
final class StubNowPlayingProvider: NowPlayingProvider {
    var current: NowPlayingInfo? { nil }
    func start() {}
    func togglePlayPause() {}
    func nextTrack() {}
    func previousTrack() {}
}
