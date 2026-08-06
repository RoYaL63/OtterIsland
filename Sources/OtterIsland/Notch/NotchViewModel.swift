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
    /// 284 de base : l'accueil en grille (indicateurs + mini calendrier +
    /// lecteur + petites actions) a besoin de cette hauteur pour ne rien couper.
    /// Les 48 pt gagnés sur les 236 d'avant sont l'air des tuiles groupées façon
    /// Centre de contrôle : chaque module porte ses propres marges intérieures,
    /// ce qu'un empilement séparé par des filets ne payait pas. Détail du budget
    /// au pire cas — barre d'onglets 30, tuiles du haut 132 (le mini calendrier
    /// à 6 semaines commande), tuile lecteur 38, écarts 17, chrome haut/bas 52.
    var expandedSize: CGSize {
        let dropOffset = settings.dropOffset(for: currentScreenID ?? "")
        return CGSize(width: 460, height: 284 + CGFloat(dropOffset))
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
    let memory = MemoryMonitor()

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
        memory.start()
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

        // IMPORTANT : la vue lit keyboardLocker À TRAVERS le view model — sans
        // cette republication, un changement de isLocked/permissionDenied ne
        // rafraîchissait jamais l'UI (recomputeMood masquait le problème pour
        // isLocked, mais permissionDenied ne change pas l'humeur : la carte
        // « Verrouillage impossible » restait figée et son bouton Fermer
        // semblait mort).
        keyboardLocker.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // La pression mémoire pilote l'humeur (loutre essoufflée en full RAM).
        memory.$pressure
            .removeDuplicates()
            .sink { [weak self] _ in self?.recomputeMood() }
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
        // Chaque capture entre aussi dans l'historique du presse-papier : ⌥V
        // depuis un champ de texte → clic sur la capture → collée, sans passer
        // par « copier » manuellement.
        if settings.clipboardEnabled {
            clipboard.addScreenshot(at: shot.url)
        }
        // …et surtout, elle part DIRECTEMENT dans le presse-papier système :
        // `screencapture` n'écrit que sur le disque, donc ⌘V juste après une
        // capture collait encore le contenu précédent.
        if settings.screenshotAutoCopy {
            clipboard.copyFile(at: shot.url)
        }
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

    /// Remet une capture de l'historique dans le presse-papier (bouton Copier
    /// de l'onglet Captures).
    func copyScreenshot(_ url: URL) {
        clipboard.copyFile(at: url)
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
        } else if memory.pressure != .normal {
            // RAM saturée : elle s'essouffle (prioritaire sur le jeu/la nage,
            // c'est un signal d'alerte, pas une ambiance).
            mood = .overloaded
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
        // Grande encoche dans les deux cas : verrouillé (le bouton Déverrouiller
        // doit rester visible) comme refusé (l'explication des permissions aussi).
        if keyboardLocker.isLocked || keyboardLocker.permissionDenied {
            setExpanded(true)
        }
        recomputeMood()
    }

    func unlockCleanup() {
        keyboardLocker.unlock()
        recomputeMood()
        setExpanded(false)
    }

    func setExpanded(_ expanded: Bool) {
        // Clavier verrouillé pour le nettoyage : l'encoche RESTE grande, quoi
        // qu'il arrive (survol, poller, molette). Le bouton Déverrouiller doit
        // être visible en permanence — c'est la seule sortie.
        if !expanded && (keyboardLocker.isLocked || keyboardLocker.permissionDenied) {
            return
        }
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
    /// simule Cmd+V dans l'app active — le panneau ne prend jamais le focus, le
    /// champ de texte de l'utilisateur est donc resté actif.
    func pasteFromClipboard(_ item: ClipboardItem) {
        clipboard.restore(item)
        setExpanded(false)
        guard Paster.hasAccessibility else {
            // Sans permission, Paster.paste() échouait EN SILENCE et l'utilisateur
            // devait faire ⌘V à la main sans comprendre pourquoi. On déclenche la
            // demande système ; l'item est déjà dans le presse-papier en attendant.
            Paster.ensureAccessibility()
            return
        }
        // 0.25 s : le temps que l'animation de repli rende la main à l'app active.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Paster.paste()
        }
    }
}
