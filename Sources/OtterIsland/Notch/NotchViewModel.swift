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
    @Published var selectedTab: NotchTab = .home

    /// Taille de la carte étendue. Partagée entre la vue (frame de l'île) et le
    /// contrôleur (zone de survol pour le suivi souris) : les deux DOIVENT voir
    /// la même géométrie, sinon la carte se replie sous le curseur.
    /// 420 × 276. La carte a MAIGRI de 40 pt en largeur en perdant la colonne
    /// de la loutre (56 pt + 12 d'écart), et le contenu y a pourtant gagné :
    /// les tuiles disposent de 388 pt au lieu de 344.
    ///
    /// Budget vertical au pire cas — barre d'onglets 30, tuiles du haut 132 (le
    /// mini calendrier à 6 semaines commande), tuile du bas 38, écarts 17,
    /// chrome haut/bas 52. Soit 269 : les 7 pt restants sont la marge.
    var expandedSize: CGSize {
        let dropOffset = settings.dropOffset(for: currentScreenID ?? "")
        return CGSize(width: 420, height: 276 + CGFloat(dropOffset))
    }

    let settings: OtterSettings
    let battery = BatteryMonitor()
    let inbox = ClaudeCodeInbox()
    let nowPlaying = AppleScriptNowPlaying()
    let calendar = CalendarProvider()
    let shelf = ShelfModel()
    let volume = VolumeMonitor()
    /// Construit dans `init` : il lit ses durées dans les réglages.
    let pomodoro: PomodoroTimer
    let clipboard = ClipboardManager()
    let screenshot = ScreenshotWatcher()
    let keyboardLocker = KeyboardLocker()
    let memory = MemoryMonitor()
    /// Relevé CPU / thermique de l'onglet Moniteur. Ne tourne que pendant que
    /// l'onglet est affiché (voir `MonitorPanel`).
    let systemMonitor = SystemMonitor()
    /// Fenêtre détaillée du moniteur, créée à la première ouverture.
    private lazy var monitorWindow = MonitorWindowController(
        monitor: systemMonitor, memory: memory, battery: battery
    )

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
        self.pomodoro = PomodoroTimer(settings: settings)
        wirePomodoro()
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

        // L'agenda se recharge toutes les minutes : c'est ce relevé qui fait
        // basculer la loutre en « RDV imminent » sans minuterie supplémentaire,
        // et qui la fait passer en humeur de nuit au fil des heures.
        calendar.$events
            .sink { [weak self] _ in self?.recomputeMood() }
            .store(in: &cancellables)

        // Un fichier atterrit sur l'étagère : elle l'attrape au vol. Comparaison
        // sur le nombre d'items pour ne réagir qu'aux AJOUTS — un retrait ne
        // mérite pas de fête.
        shelf.$items
            .scan((0, false)) { previous, items in (items.count, items.count > previous.0) }
            .filter(\.1)
            .sink { [weak self] _ in
                self?.otterEvent = OtterEventToken(event: .caught)
            }
            .store(in: &cancellables)
    }

    /// Ouvre le moniteur détaillé. La carte de l'encoche reste lisible d'un
    /// coup d'œil ; tout ce qui demande de la place vit dans cette fenêtre.
    func openMonitorWindow() {
        monitorWindow.show()
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

    /// Branche le Pomodoro sur le reste du monde : Concentration système,
    /// musique, humeur de la loutre. Le minuteur ne connaît aucun de ces
    /// modules — il se contente de dire « ça commence » et « ça se termine ».
    private func wirePomodoro() {
        pomodoro.onWorkStart = { [weak self] in
            guard let self else { return }
            FocusMode.trigger(self.settings.pomodoroFocusShortcutOn)
            // Couper la musique fait partie de « se mettre au travail » pour
            // certains, pas pour tous : d'où le réglage. On ne coupe que si ça
            // joue vraiment, sinon la bascule play/pause RELANCERAIT la lecture.
            if self.settings.pomodoroPauseMusic, self.nowPlaying.current?.isPlaying == true {
                self.nowPlaying.togglePlayPause()
            }
            self.recomputeMood()
        }
        pomodoro.onWorkEnd = { [weak self] completed in
            guard let self else { return }
            FocusMode.trigger(self.settings.pomodoroFocusShortcutOff)
            if completed {
                self.otterEvent = OtterEventToken(event: .pomodoroDone)
            }
            self.recomputeMood()
        }
        // La rangée Pomodoro de l'accueil lit `phase` et `remaining` à travers
        // le view model : sans republication, la jauge resterait figée.
        pomodoro.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
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
        // Flash d'appareil photo côté loutre : la capture vient d'être prise,
        // elle doit se voir dans la seconde, pas seulement dans une carte.
        otterEvent = OtterEventToken(event: .snapshot)
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

    /// Ordre de priorité, du plus urgent au plus ambiant. Les ALERTES passent
    /// devant tout : une batterie à 8 % doit se voir même en pleine session de
    /// concentration. Vient ensuite ce que l'utilisateur a explicitement lancé
    /// (Pomodoro), puis ce qui approche (un RDV), puis l'ambiance (musique,
    /// charge, nuit, inactivité).
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
        } else if pomodoro.isRunning && pomodoro.phase == .work {
            // Passe devant l'ouverture de l'encoche : pendant une session, le
            // seul message qui compte est « tu es en train de bosser ».
            mood = .focused
        } else if meetingIsImminent {
            mood = .meetingSoon
        } else if isExpanded {
            mood = .playful
        } else if musicPlaying {
            mood = .swimming
        } else if battery.isCharging {
            mood = .happy
        } else if isSleepy {
            mood = .sleepy
        } else if isNight {
            mood = .night
        } else {
            mood = .idle
        }

        guard mood != otterMood else { return }
        otterMood = mood
    }

    /// Un rendez-vous commence dans moins de 5 minutes (et n'a pas déjà
    /// commencé). C'est la fenêtre où un rappel sert encore à quelque chose.
    private var meetingIsImminent: Bool {
        guard let next = calendar.events.first else { return false }
        let delay = next.start.timeIntervalSinceNow
        return delay > 0 && delay <= 5 * 60
    }

    /// Entre 22 h et 6 h. Sert d'ambiance par défaut à la place de `.idle` :
    /// la loutre n'a pas la même tête à 3 h du matin qu'à 10 h.
    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 6
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
        // Valeurs que ship Apple pour un tiroir / une feuille (« Designing
        // Fluid Interfaces ») : amortissement 0,8 et réponse 0,3 s. L'île EST
        // un tiroir. Le réglage d'avant (0,68 / 0,40) rebondissait plus et
        // arrivait plus tard : le dépassement se voyait comme un effet, là où
        // celui-ci se ressent comme une matière qui se pose.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
