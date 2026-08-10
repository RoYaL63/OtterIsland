import Foundation
import AppKit
import Combine

/// Minuteur Pomodoro. Ce n'était qu'un décompte de 25 min figé, qui n'agissait
/// sur rien : il gère maintenant les deux phases (travail / pause), lit ses
/// durées dans les réglages, et surtout PRÉVIENT quand une session commence et
/// se termine — c'est ce qui permet au reste de l'app de mettre le Mac en
/// Concentration, de couper la musique et de changer l'humeur de la loutre.
///
/// Le minuteur ne pilote rien lui-même : il expose `onWorkStart` / `onWorkEnd`
/// et laisse le view model brancher les effets. Un minuteur qui saurait parler
/// à Raccourcis, à Spotify et à SpriteKit ne serait plus testable ni lisible.
@MainActor
final class PomodoroTimer: ObservableObject {

    enum Phase: String {
        case idle, work, rest

        var label: String {
            switch self {
            case .idle: return "Pomodoro"
            case .work: return "Concentration"
            case .rest: return "Pause"
            }
        }

        var icon: String {
            switch self {
            case .idle: return "timer"
            case .work: return "moon.fill"
            case .rest: return "cup.and.saucer.fill"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isRunning = false

    /// Début d'une session de travail (démarrage ou reprise après pause).
    var onWorkStart: (() -> Void)?
    /// Fin d'une session de travail. `completed` distingue « le minuteur est
    /// allé au bout » d'un arrêt manuel : seule la première mérite une fête.
    var onWorkEnd: ((_ completed: Bool) -> Void)?

    private let settings: OtterSettings
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: OtterSettings) {
        self.settings = settings
        remaining = TimeInterval(settings.pomodoroWorkMinutes * 60)

        // Changer la durée dans les réglages doit se voir tout de suite dans
        // l'encoche — mais jamais au milieu d'une session en cours.
        settings.$pomodoroWorkMinutes
            .dropFirst()
            .sink { [weak self] minutes in
                guard let self, self.phase == .idle else { return }
                self.remaining = TimeInterval(minutes * 60)
            }
            .store(in: &cancellables)
    }

    // MARK: Commandes

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        if phase == .idle {
            phase = .work
            remaining = TimeInterval(settings.pomodoroWorkMinutes * 60)
        }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if phase == .work { onWorkStart?() }
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        // Mettre en pause, c'est sortir de la concentration : la Concentration
        // système doit retomber, sinon les notifications restent bloquées sans
        // que rien ne l'indique.
        if phase == .work { onWorkEnd?(false) }
    }

    func reset() {
        let wasWorking = isRunning && phase == .work
        isRunning = false
        timer?.invalidate()
        timer = nil
        phase = .idle
        remaining = TimeInterval(settings.pomodoroWorkMinutes * 60)
        if wasWorking { onWorkEnd?(false) }
    }

    // MARK: Cycle

    private func tick() {
        remaining = max(0, remaining - 1)
        guard remaining == 0 else { return }
        finishPhase()
    }

    private func finishPhase() {
        chime()
        switch phase {
        case .work:
            onWorkEnd?(true)
            if settings.pomodoroAutoStartBreak, settings.pomodoroBreakMinutes > 0 {
                phase = .rest
                remaining = TimeInterval(settings.pomodoroBreakMinutes * 60)
                return // le minuteur continue de tourner sur la pause
            }
            stopAtIdle()
        case .rest:
            stopAtIdle()
        case .idle:
            stopAtIdle()
        }
    }

    private func stopAtIdle() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        phase = .idle
        remaining = TimeInterval(settings.pomodoroWorkMinutes * 60)
    }

    /// Son système plutôt qu'une notification : l'utilisateur vient justement de
    /// demander à ne PAS être notifié, et une bannière percerait la
    /// Concentration qu'on a nous-mêmes activée.
    private func chime() {
        guard settings.pomodoroChime else { return }
        NSSound(named: phase == .work ? "Glass" : "Submarine")?.play()
    }

    // MARK: Affichage

    var display: String {
        let total = Int(remaining)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Durée configurée d'une session, pour les libellés de l'interface. Évite
    /// aux vues d'avoir à connaître `OtterSettings` juste pour afficher « 25 min ».
    var workMinutes: Int { settings.pomodoroWorkMinutes }

    /// Avancement de la phase en cours, 0…1, pour la jauge de la rangée.
    /// nil au repos : une barre vide sous un minuteur à l'arrêt ne dit rien.
    var progress: Double? {
        guard phase != .idle else { return nil }
        let total = phase == .work
            ? Double(settings.pomodoroWorkMinutes * 60)
            : Double(settings.pomodoroBreakMinutes * 60)
        guard total > 0 else { return nil }
        return 1 - (remaining / total)
    }
}
