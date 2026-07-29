import SwiftUI
import AppKit
import Combine

/// Agrège les providers et l'état d'affichage. Pas de logique métier ici :
/// chaque module fait son travail, le view model relaie.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var metrics: NotchMetrics?
    /// Identifiant stable de l'écran actif, pour appliquer les réglages par écran.
    @Published var currentScreenID: String?
    @Published var otterMood: OtterMood = .idle
    /// Dernier événement ponctuel joué par la loutre (coquillage, etc.).
    @Published var otterEvent: OtterEventToken?
    @Published var selectedTab: NotchTab = .otter

    /// Taille de la carte étendue. Partagée entre la vue (frame de l'île) et le
    /// contrôleur (zone de survol pour le suivi souris) : les deux DOIVENT voir
    /// la même géométrie, sinon la carte se replie sous le curseur.
    /// 224 de base (pas 176) : le panneau par défaut affiche le prochain RDV,
    /// la musique et les actions rapides — 176 coupait le contenu.
    var expandedSize: CGSize {
        let dropOffset = settings.dropOffset(for: currentScreenID ?? "")
        return CGSize(width: 460, height: 224 + CGFloat(dropOffset))
    }

    let settings: OtterSettings
    let battery = BatteryMonitor()
    let inbox = ClaudeCodeInbox()
    let nowPlaying = AppleScriptNowPlaying()
    let calendar = CalendarProvider()
    let shelf = ShelfModel()
    let volume = VolumeMonitor()
    let pomodoro = PomodoroTimer()
    let clipboard = ClipboardManager()
    let screenshot = ScreenshotWatcher()
    let keyboardLocker = KeyboardLocker()

    /// HUD système transitoire (volume…), effacé automatiquement.
    @Published var hud: HUDState?
    private var hudClearTimer: Timer?

    /// Aperçu transitoire de la dernière capture d'écran, effacé automatiquement.
    @Published var screenshotPreview: ScreenshotWatcher.Shot?
    private var screenshotClearTimer: Timer?

    /// Seuil de batterie sous lequel la loutre s'inquiète.
    private let lowBatteryThreshold = 15
    /// Délai d'inactivité avant que la loutre s'endorme.
    private let sleepDelay: TimeInterval = 30
    private var sleepTimer: Timer?
    private var isSleepy = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: OtterSettings) {
        self.settings = settings
        if settings.claudeCodeInboxEnabled {
            inbox.start()
        }
        if settings.musicFollow {
            nowPlaying.start()
        }
        calendar.start()
        volume.start()
        if settings.clipboardEnabled {
            clipboard.start()
        }
        if settings.screenshotPreviewEnabled {
            screenshot.start()
        }
        wireMood()
        wireCelebrations()
        wireHUD()
        wireScreenshot()

        // Rafraîchit la vue quand le morceau change (même si l'humeur ne bouge pas).
        nowPlaying.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Recalcule l'humeur à chaque signal de contexte et relance la minuterie de sommeil.
    private func wireMood() {
        let core = Publishers.CombineLatest4(
            battery.$isCharging,
            battery.$percentage,
            inbox.$pending,
            $isExpanded
        )
        core.combineLatest(nowPlaying.$current)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.resetSleepTimer()
                self.recomputeMood()
            }
            .store(in: &cancellables)
    }

    /// Une approbation d'action Claude Code déclenche la petite fête.
    private func wireCelebrations() {
        inbox.decisions
            .filter { $0 } // seulement les « approuvé »
            .sink { [weak self] _ in
                self?.otterEvent = OtterEventToken(event: .celebrate)
            }
            .store(in: &cancellables)
    }

    /// Affiche un HUD de volume à chaque changement (en ignorant la valeur initiale).
    private func wireHUD() {
        volume.$volume
            .dropFirst()
            .sink { [weak self] value in
                self?.showHUD(HUDState(kind: .volume, value: Double(value)))
            }
            .store(in: &cancellables)
    }

    private func showHUD(_ state: HUDState) {
        hud = state
        hudClearTimer?.invalidate()
        hudClearTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.2)) { self?.hud = nil }
            }
        }
    }

    /// Affiche un aperçu à chaque nouvelle capture d'écran détectée, effacé après 5 s.
    private func wireScreenshot() {
        screenshot.$latest
            .compactMap { $0 }
            .sink { [weak self] shot in
                self?.showScreenshot(shot)
            }
            .store(in: &cancellables)
    }

    private func showScreenshot(_ shot: ScreenshotWatcher.Shot) {
        screenshotPreview = shot
        screenshotClearTimer?.invalidate()
        screenshotClearTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.2)) { self?.screenshotPreview = nil }
            }
        }
    }

    /// Ouvre la capture dans l'app par défaut (Aperçu) et referme la carte.
    func openScreenshotPreview() {
        guard let shot = screenshotPreview else { return }
        NSWorkspace.shared.open(shot.url)
        dismissScreenshotPreview()
    }

    func dismissScreenshotPreview() {
        screenshotClearTimer?.invalidate()
        withAnimation(.easeOut(duration: 0.2)) { screenshotPreview = nil }
    }

    private func recomputeMood() {
        let lowBattery = battery.percentage <= lowBatteryThreshold && !battery.isCharging
        let musicPlaying = settings.musicFollow && (nowPlaying.current?.isPlaying ?? false)

        let mood: OtterMood
        if keyboardLocker.isLocked {
            mood = .cleaning
        } else if inbox.pending != nil {
            mood = .curious
        } else if lowBattery {
            mood = .worried
        } else if isExpanded {
            mood = .playful
        } else if musicPlaying {
            mood = .swimming
        } else if battery.isCharging {
            mood = .happy
        } else if isSleepy {
            mood = .sleepy
        } else {
            mood = .idle
        }

        guard mood != otterMood else { return }
        otterMood = mood
    }

    private func resetSleepTimer() {
        isSleepy = false
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: sleepDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isSleepy = true
                self?.recomputeMood()
            }
        }
    }

    /// Verrouille/déverrouille le clavier pour le nettoyage. On force l'encoche
    /// ouverte au verrouillage pour que le bouton de déverrouillage reste visible.
    func toggleCleanup() {
        keyboardLocker.toggle()
        if keyboardLocker.isLocked {
            setExpanded(true)
        }
        recomputeMood()
    }

    func unlockCleanup() {
        keyboardLocker.unlock()
        recomputeMood()
    }

    func setExpanded(_ expanded: Bool) {
        // Amortissement < 0.7 : léger dépassement élastique, l'île « goutte
        // d'eau » rebondit un peu en se déployant, façon Dynamic Island.
        withAnimation(.spring(response: 0.40, dampingFraction: 0.68)) {
            isExpanded = expanded
        }
    }

    /// Ouvre le presse-papier dans l'encoche (appelé par le raccourci global).
    func openClipboard() {
        selectedTab = .clipboard
        setExpanded(true)
    }

    /// Colle l'item choisi : on le remet dans le presse-papier, on ferme, puis on
    /// simule Cmd+V dans l'app active.
    func pasteFromClipboard(_ item: ClipboardItem) {
        clipboard.restore(item)
        setExpanded(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Paster.paste()
        }
    }
}
