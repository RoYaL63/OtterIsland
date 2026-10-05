import SwiftUI
import Combine
import Carbon.HIToolbox

/// État persistant de l'app. Simple wrapper UserDefaults exposé en @Published
/// pour que les vues SwiftUI se rafraîchissent. Un réglage = une propriété.
final class OtterSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var otterEnabled: Bool {
        didSet { defaults.set(otterEnabled, forKey: Keys.otterEnabled) }
    }

    @Published var showBattery: Bool {
        didSet { defaults.set(showBattery, forKey: Keys.showBattery) }
    }

    @Published var claudeCodeInboxEnabled: Bool {
        didSet { defaults.set(claudeCodeInboxEnabled, forKey: Keys.claudeInbox) }
    }

    /// Suivi de la musique : fait nager la loutre quand un morceau joue.
    @Published var musicFollow: Bool {
        didSet { defaults.set(musicFollow, forKey: Keys.musicFollow) }
    }

    /// Ouvre/ferme l'encoche à la molette au-dessus d'elle.
    @Published var gestureControl: Bool {
        didSet { defaults.set(gestureControl, forKey: Keys.gestureControl) }
    }

    /// Historique du presse-papier accessible par raccourci.
    @Published var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled) }
    }

    /// Raccourci global d'ouverture du presse-papier (keyCode + modificateurs Carbon,
    /// capturés par `ShortcutRecorderView`). Par défaut Option+V : une seule main,
    /// et disponible pendant la frappe dans n'importe quel champ de texte — le but
    /// est de coller sans quitter la barre de chat. Nécessite un redémarrage de
    /// l'app après changement (le hotkey n'est installé qu'au lancement).
    @Published var clipboardHotKeyCode: Int {
        didSet { defaults.set(clipboardHotKeyCode, forKey: Keys.clipboardHotKeyCode) }
    }

    @Published var clipboardHotKeyModifiers: Int {
        didSet { defaults.set(clipboardHotKeyModifiers, forKey: Keys.clipboardHotKeyModifiers) }
    }

    /// État d'exécution (pas persisté) : true si la dernière tentative d'enregistrement
    /// du raccourci global a échoué (combinaison déjà prise ailleurs, par exemple).
    @Published var clipboardHotKeyRegistrationFailed = false

    /// Aperçu transitoire dans l'encoche à chaque nouvelle capture d'écran.
    @Published var screenshotPreviewEnabled: Bool {
        didSet { defaults.set(screenshotPreviewEnabled, forKey: Keys.screenshotPreviewEnabled) }
    }

    /// Copie automatiquement chaque nouvelle capture dans le presse-papier :
    /// ⌘⇧4 puis ⌘V, sans étape intermédiaire.
    @Published var screenshotAutoCopy: Bool {
        didSet { defaults.set(screenshotAutoCopy, forKey: Keys.screenshotAutoCopy) }
    }

    /// Relevé léger (une fois par minute) des applications qui pèsent, pour
    /// repérer celles qui ralentissent le Mac de façon récurrente.
    @Published var monitorHistoryEnabled: Bool {
        didSet { defaults.set(monitorHistoryEnabled, forKey: Keys.monitorHistory) }
    }

    /// Note le titre des pages ouvertes quand un navigateur s'emballe. Reste
    /// sur ce Mac, mais c'est un historique de navigation partiel : réglable.
    @Published var monitorRecordPageTitles: Bool {
        didSet { defaults.set(monitorRecordPageTitles, forKey: Keys.monitorPageTitles) }
    }

    /// Cherche une nouvelle version au lancement (une seule requête GitHub).
    @Published var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }

    // MARK: Ouverture de l'encoche

    /// Le survol ouvre l'île. Décochable : c'est la seule façon d'être certain
    /// qu'elle ne s'ouvrira jamais toute seule (la molette et le raccourci
    /// continuent de marcher).
    @Published var hoverToOpen: Bool {
        didSet { defaults.set(hoverToOpen, forKey: Keys.hoverToOpen) }
    }

    /// Temps d'ARRÊT exigé sur l'encoche avant qu'elle s'ouvre, en secondes.
    /// Ce n'est pas un simple délai : le pointeur doit rester immobile (voir
    /// `NotchWindowController`). Traverser la zone pour aller cliquer un onglet
    /// du navigateur n'ouvre donc rien, quelle que soit la lenteur du geste.
    @Published var hoverOpenDelay: Double {
        didSet { defaults.set(hoverOpenDelay, forKey: Keys.hoverOpenDelay) }
    }

    // MARK: Pomodoro et Concentration

    /// Durée d'une session de travail, en minutes.
    @Published var pomodoroWorkMinutes: Int {
        didSet { defaults.set(pomodoroWorkMinutes, forKey: Keys.pomodoroWork) }
    }

    /// Durée de la pause enchaînée après une session. 0 = pas de pause.
    @Published var pomodoroBreakMinutes: Int {
        didSet { defaults.set(pomodoroBreakMinutes, forKey: Keys.pomodoroBreak) }
    }

    /// La pause démarre toute seule à la fin d'une session.
    @Published var pomodoroAutoStartBreak: Bool {
        didSet { defaults.set(pomodoroAutoStartBreak, forKey: Keys.pomodoroAutoBreak) }
    }

    /// Raccourci (app Raccourcis) lancé au début d'une session : c'est lui qui
    /// met le Mac en Concentration. Vide = la fonction est inactive. Voir
    /// `FocusMode` pour pourquoi il faut passer par Raccourcis.
    @Published var pomodoroFocusShortcutOn: String {
        didSet { defaults.set(pomodoroFocusShortcutOn, forKey: Keys.pomodoroFocusOn) }
    }

    /// Raccourci lancé à la fin d'une session, pour couper la Concentration.
    @Published var pomodoroFocusShortcutOff: String {
        didSet { defaults.set(pomodoroFocusShortcutOff, forKey: Keys.pomodoroFocusOff) }
    }

    /// Met la musique en pause pendant une session de travail.
    @Published var pomodoroPauseMusic: Bool {
        didSet { defaults.set(pomodoroPauseMusic, forKey: Keys.pomodoroPauseMusic) }
    }

    /// Son système à la fin d'une phase.
    @Published var pomodoroChime: Bool {
        didSet { defaults.set(pomodoroChime, forKey: Keys.pomodoroChime) }
    }

    /// Ajustement fin de la largeur de l'encoche, en points. Négatif = plus étroit.
    /// Sert de valeur par défaut pour un écran sans réglage propre.
    @Published var notchWidthOffset: Double {
        didSet { defaults.set(notchWidthOffset, forKey: Keys.widthOffset) }
    }

    /// Décalage vertical de la carte étendue sous l'encoche. Valeur par défaut,
    /// idem `notchWidthOffset`.
    @Published var expandedDropOffset: Double {
        didSet { defaults.set(expandedDropOffset, forKey: Keys.dropOffset) }
    }

    /// Overrides par écran (clé = `ScreenIdentifier.stableID`), pour les setups
    /// multi-écrans où chaque moniteur a une géométrie différente.
    @Published var perScreenWidthOffset: [String: Double] {
        didSet { defaults.set(perScreenWidthOffset, forKey: Keys.perScreenWidthOffset) }
    }

    @Published var perScreenDropOffset: [String: Double] {
        didSet { defaults.set(perScreenDropOffset, forKey: Keys.perScreenDropOffset) }
    }

    /// Sur quel écran vit l'île (voir `IslandScreenMode`).
    @Published var islandScreenMode: IslandScreenMode {
        didSet { defaults.set(islandScreenMode.rawValue, forKey: Keys.islandScreenMode) }
    }

    /// Écran choisi en mode `.fixed` (`ScreenIdentifier.stableID`). Vide =
    /// l'écran du MacBook, ou à défaut celui sous le pointeur.
    @Published var islandFixedScreenID: String {
        didSet { defaults.set(islandFixedScreenID, forKey: Keys.islandFixedScreenID) }
    }

    /// Caméra du miroir (`AVCaptureDevice.uniqueID`). Vide = la caméra
    /// frontale du Mac, ou à défaut la première trouvée.
    @Published var mirrorCameraID: String {
        didSet { defaults.set(mirrorCameraID, forKey: Keys.mirrorCameraID) }
    }

    /// Image inversée comme dans un miroir (ce que tu vois de toi), ou telle
    /// que les autres la verront en visio.
    @Published var mirrorFlipped: Bool {
        didSet { defaults.set(mirrorFlipped, forKey: Keys.mirrorFlipped) }
    }

    /// Remplir le cadre (recadré) plutôt que montrer tout le champ (bandes).
    @Published var mirrorFill: Bool {
        didSet { defaults.set(mirrorFill, forKey: Keys.mirrorFill) }
    }

    // MARK: Fonctionnalités (Réglages › Fonctionnalités)

    /// Ordre des onglets de l'île (`NotchTab.rawValue`). Un onglet absent de
    /// la liste (ajouté dans une version future) se range à la fin.
    @Published var tabOrder: [String] {
        didSet { defaults.set(tabOrder, forKey: Keys.tabOrder) }
    }

    /// Onglets masqués de la barre de l'île.
    @Published var hiddenTabs: [String] {
        didSet { defaults.set(hiddenTabs, forKey: Keys.hiddenTabs) }
    }

    /// Bulle de volume dans l'encoche. Doublon de celle de macOS : on peut la couper.
    @Published var volumeHUDEnabled: Bool {
        didSet { defaults.set(volumeHUDEnabled, forKey: Keys.volumeHUD) }
    }

    /// Onglet Musique : curseur de volume. Garde la clé de la 1.5.0, où il
    /// allait de pair avec le bouton couper : le réglage existant est conservé.
    @Published var musicShowVolumeSlider: Bool {
        didSet { defaults.set(musicShowVolumeSlider, forKey: Keys.musicShowVolume) }
    }

    /// Onglet Musique : bouton couper / rétablir le son.
    @Published var musicShowMuteButton: Bool {
        didSet { defaults.set(musicShowMuteButton, forKey: Keys.musicShowMute) }
    }

    /// Onglet Musique : bouton pour ouvrir Spotify ou Musique.
    @Published var musicShowOpenApp: Bool {
        didSet { defaults.set(musicShowOpenApp, forKey: Keys.musicShowOpenApp) }
    }

    /// Éléments de l'accueil masqués (`HomeItem.rawValue`).
    @Published var hiddenHomeItems: [String] {
        didSet { defaults.set(hiddenHomeItems, forKey: Keys.hiddenHomeItems) }
    }

    /// Onglet Raccourcis dédié dans l'île. Par défaut, les raccourcis vivent
    /// en bas de l'accueil : un onglet de plus encombrait la barre.
    @Published var shortcutsTabEnabled: Bool {
        didSet { defaults.set(shortcutsTabEnabled, forKey: Keys.shortcutsTab) }
    }

    // MARK: Barre des menus (Réglages › Raccourcis et barre)

    /// Flèche et séparateur pour plier la barre des menus (`MenuBarManager`).
    @Published var menuBarManagerEnabled: Bool {
        didSet { defaults.set(menuBarManagerEnabled, forKey: Keys.menuBarManager) }
    }

    /// Replier la barre au lancement d'OtterIsland.
    @Published var menuBarCollapseAtLaunch: Bool {
        didSet { defaults.set(menuBarCollapseAtLaunch, forKey: Keys.menuBarCollapseAtLaunch) }
    }

    /// Replier tout seul après ce délai (secondes). 0 = jamais.
    @Published var menuBarAutoCollapseDelay: Double {
        didSet { defaults.set(menuBarAutoCollapseDelay, forKey: Keys.menuBarAutoCollapse) }
    }

    // MARK: Assistants IA (Réglages › Assistants IA)

    /// Surveiller Claude Code : tokens et session en cours.
    @Published var aiClaudeCodeEnabled: Bool {
        didSet { defaults.set(aiClaudeCodeEnabled, forKey: Keys.aiClaudeCode) }
    }

    /// Surveiller Codex : tokens et session en cours.
    @Published var aiCodexEnabled: Bool {
        didSet { defaults.set(aiCodexEnabled, forKey: Keys.aiCodex) }
    }

    var enabledAssistants: [AIAssistant] {
        AIAssistant.allCases.filter {
            switch $0 {
            case .claudeCode: return aiClaudeCodeEnabled
            case .codex: return aiCodexEnabled
            }
        }
    }

    /// Onglets visibles, dans l'ordre choisi. Jamais vide : si tout est
    /// masqué, l'accueil reste, sinon l'île n'aurait plus rien à montrer.
    var visibleTabs: [NotchTab] {
        let ordered = tabOrder.compactMap(NotchTab.init(rawValue:))
        let all = ordered + NotchTab.allCases.filter { !ordered.contains($0) }
        // L'onglet IA n'a rien à montrer tant qu'aucun assistant n'est suivi.
        let visible = all.filter {
            !hiddenTabs.contains($0.rawValue)
                && ($0 != .ai || !enabledAssistants.isEmpty)
                && ($0 != .shortcuts || shortcutsTabEnabled)
        }
        return visible.isEmpty ? [.home] : visible
    }

    /// Tous les onglets dans l'ordre choisi, masqués compris (pour les réglages).
    var orderedTabs: [NotchTab] {
        let ordered = tabOrder.compactMap(NotchTab.init(rawValue:))
        return ordered + NotchTab.allCases.filter { !ordered.contains($0) }
    }

    func isTabVisible(_ tab: NotchTab) -> Bool { !hiddenTabs.contains(tab.rawValue) }

    func setTab(_ tab: NotchTab, visible: Bool) {
        hiddenTabs.removeAll { $0 == tab.rawValue }
        if !visible { hiddenTabs.append(tab.rawValue) }
    }

    /// Déplace un onglet d'un cran (-1 = vers la gauche, +1 = vers la droite).
    func moveTab(_ tab: NotchTab, by offset: Int) {
        var order = orderedTabs
        guard let index = order.firstIndex(of: tab) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        tabOrder = order.map(\.rawValue)
    }

    func isHomeItemVisible(_ item: HomeItem) -> Bool { !hiddenHomeItems.contains(item.rawValue) }

    func setHomeItem(_ item: HomeItem, visible: Bool) {
        hiddenHomeItems.removeAll { $0 == item.rawValue }
        if !visible { hiddenHomeItems.append(item.rawValue) }
    }

    init() {
        defaults.register(defaults: [
            Keys.otterEnabled: false,
            Keys.showBattery: true,
            Keys.claudeInbox: true,
            Keys.musicFollow: true,
            Keys.gestureControl: true,
            Keys.clipboardEnabled: true,
            Keys.clipboardHotKeyCode: Int(kVK_ANSI_V),
            Keys.clipboardHotKeyModifiers: Int(optionKey),
            Keys.screenshotPreviewEnabled: true,
            Keys.screenshotAutoCopy: true,
            Keys.autoCheckUpdates: true,
            Keys.monitorHistory: true,
            Keys.monitorPageTitles: true,
            Keys.widthOffset: 0.0,
            Keys.dropOffset: 0.0,
            Keys.hoverToOpen: true,
            Keys.hoverOpenDelay: 0.45,
            Keys.pomodoroWork: 25,
            Keys.pomodoroBreak: 5,
            Keys.pomodoroAutoBreak: true,
            Keys.pomodoroFocusOn: "",
            Keys.pomodoroFocusOff: "",
            Keys.pomodoroPauseMusic: false,
            Keys.pomodoroChime: true,
            Keys.islandScreenMode: IslandScreenMode.fixed.rawValue,
            Keys.islandFixedScreenID: "",
            Keys.mirrorCameraID: "",
            Keys.mirrorFlipped: true,
            Keys.mirrorFill: false,
            Keys.volumeHUD: true,
            Keys.musicShowVolume: true,
            Keys.musicShowMute: true,
            Keys.aiClaudeCode: false,
            Keys.aiCodex: false,
            Keys.menuBarManager: false,
            Keys.shortcutsTab: false,
            Keys.menuBarCollapseAtLaunch: true,
            Keys.menuBarAutoCollapse: 15.0,
            Keys.musicShowOpenApp: true,
        ])
        otterEnabled = defaults.bool(forKey: Keys.otterEnabled)
        showBattery = defaults.bool(forKey: Keys.showBattery)
        claudeCodeInboxEnabled = defaults.bool(forKey: Keys.claudeInbox)
        musicFollow = defaults.bool(forKey: Keys.musicFollow)
        gestureControl = defaults.bool(forKey: Keys.gestureControl)
        clipboardEnabled = defaults.bool(forKey: Keys.clipboardEnabled)
        clipboardHotKeyCode = defaults.integer(forKey: Keys.clipboardHotKeyCode)
        clipboardHotKeyModifiers = defaults.integer(forKey: Keys.clipboardHotKeyModifiers)
        screenshotPreviewEnabled = defaults.bool(forKey: Keys.screenshotPreviewEnabled)
        screenshotAutoCopy = defaults.bool(forKey: Keys.screenshotAutoCopy)
        autoCheckUpdates = defaults.bool(forKey: Keys.autoCheckUpdates)
        monitorHistoryEnabled = defaults.bool(forKey: Keys.monitorHistory)
        monitorRecordPageTitles = defaults.bool(forKey: Keys.monitorPageTitles)
        notchWidthOffset = defaults.double(forKey: Keys.widthOffset)
        expandedDropOffset = defaults.double(forKey: Keys.dropOffset)
        perScreenWidthOffset = defaults.dictionary(forKey: Keys.perScreenWidthOffset) as? [String: Double] ?? [:]
        perScreenDropOffset = defaults.dictionary(forKey: Keys.perScreenDropOffset) as? [String: Double] ?? [:]
        hoverToOpen = defaults.bool(forKey: Keys.hoverToOpen)
        hoverOpenDelay = defaults.double(forKey: Keys.hoverOpenDelay)
        pomodoroWorkMinutes = defaults.integer(forKey: Keys.pomodoroWork)
        pomodoroBreakMinutes = defaults.integer(forKey: Keys.pomodoroBreak)
        pomodoroAutoStartBreak = defaults.bool(forKey: Keys.pomodoroAutoBreak)
        pomodoroFocusShortcutOn = defaults.string(forKey: Keys.pomodoroFocusOn) ?? ""
        pomodoroFocusShortcutOff = defaults.string(forKey: Keys.pomodoroFocusOff) ?? ""
        pomodoroPauseMusic = defaults.bool(forKey: Keys.pomodoroPauseMusic)
        pomodoroChime = defaults.bool(forKey: Keys.pomodoroChime)
        islandScreenMode = IslandScreenMode(rawValue: defaults.string(forKey: Keys.islandScreenMode) ?? "") ?? .fixed
        islandFixedScreenID = defaults.string(forKey: Keys.islandFixedScreenID) ?? ""
        mirrorCameraID = defaults.string(forKey: Keys.mirrorCameraID) ?? ""
        mirrorFlipped = defaults.bool(forKey: Keys.mirrorFlipped)
        mirrorFill = defaults.bool(forKey: Keys.mirrorFill)
        tabOrder = defaults.stringArray(forKey: Keys.tabOrder) ?? NotchTab.allCases.map(\.rawValue)
        hiddenTabs = defaults.stringArray(forKey: Keys.hiddenTabs) ?? []
        volumeHUDEnabled = defaults.bool(forKey: Keys.volumeHUD)
        musicShowVolumeSlider = defaults.bool(forKey: Keys.musicShowVolume)
        musicShowMuteButton = defaults.bool(forKey: Keys.musicShowMute)
        musicShowOpenApp = defaults.bool(forKey: Keys.musicShowOpenApp)
        hiddenHomeItems = defaults.stringArray(forKey: Keys.hiddenHomeItems) ?? []
        aiClaudeCodeEnabled = defaults.bool(forKey: Keys.aiClaudeCode)
        aiCodexEnabled = defaults.bool(forKey: Keys.aiCodex)
        menuBarManagerEnabled = defaults.bool(forKey: Keys.menuBarManager)
        shortcutsTabEnabled = defaults.bool(forKey: Keys.shortcutsTab)
        menuBarCollapseAtLaunch = defaults.bool(forKey: Keys.menuBarCollapseAtLaunch)
        menuBarAutoCollapseDelay = defaults.double(forKey: Keys.menuBarAutoCollapse)
    }

    /// Largeur pour un écran donné : son réglage propre s'il existe, sinon la valeur par défaut.
    func widthOffset(for screenID: String) -> Double {
        perScreenWidthOffset[screenID] ?? notchWidthOffset
    }

    func setWidthOffset(_ value: Double, for screenID: String) {
        perScreenWidthOffset[screenID] = value
    }

    /// Débordement pour un écran donné : son réglage propre s'il existe, sinon la valeur par défaut.
    func dropOffset(for screenID: String) -> Double {
        perScreenDropOffset[screenID] ?? expandedDropOffset
    }

    func setDropOffset(_ value: Double, for screenID: String) {
        perScreenDropOffset[screenID] = value
    }

    private enum Keys {
        static let otterEnabled = "otterEnabled"
        static let showBattery = "showBattery"
        static let claudeInbox = "claudeCodeInboxEnabled"
        static let musicFollow = "musicFollow"
        static let gestureControl = "gestureControl"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardHotKeyCode = "clipboardHotKeyCode"
        static let clipboardHotKeyModifiers = "clipboardHotKeyModifiers"
        static let screenshotPreviewEnabled = "screenshotPreviewEnabled"
        static let screenshotAutoCopy = "screenshotAutoCopy"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let monitorHistory = "monitorHistoryEnabled"
        static let monitorPageTitles = "monitorRecordPageTitles"
        static let widthOffset = "notchWidthOffset"
        static let dropOffset = "expandedDropOffset"
        static let perScreenWidthOffset = "perScreenWidthOffset"
        static let perScreenDropOffset = "perScreenDropOffset"
        static let hoverToOpen = "hoverToOpen"
        static let hoverOpenDelay = "hoverOpenDelay"
        static let pomodoroWork = "pomodoroWorkMinutes"
        static let pomodoroBreak = "pomodoroBreakMinutes"
        static let pomodoroAutoBreak = "pomodoroAutoStartBreak"
        static let pomodoroFocusOn = "pomodoroFocusShortcutOn"
        static let pomodoroFocusOff = "pomodoroFocusShortcutOff"
        static let pomodoroPauseMusic = "pomodoroPauseMusic"
        static let pomodoroChime = "pomodoroChime"
        static let islandScreenMode = "islandScreenMode"
        static let islandFixedScreenID = "islandFixedScreenID"
        static let mirrorCameraID = "mirrorCameraID"
        static let mirrorFlipped = "mirrorFlipped"
        static let mirrorFill = "mirrorFill"
        static let tabOrder = "tabOrder"
        static let hiddenTabs = "hiddenTabs"
        static let volumeHUD = "volumeHUDEnabled"
        static let musicShowVolume = "musicShowVolume"
        static let musicShowMute = "musicShowMuteButton"
        static let musicShowOpenApp = "musicShowOpenApp"
        static let hiddenHomeItems = "hiddenHomeItems"
        static let aiClaudeCode = "aiClaudeCodeEnabled"
        static let aiCodex = "aiCodexEnabled"
        static let menuBarManager = "menuBarManagerEnabled"
        static let shortcutsTab = "shortcutsTabEnabled"
        static let menuBarCollapseAtLaunch = "menuBarCollapseAtLaunch"
        static let menuBarAutoCollapse = "menuBarAutoCollapseDelay"
    }
}
