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

    /// Cherche une nouvelle version au lancement (une seule requête GitHub).
    @Published var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
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

    init() {
        defaults.register(defaults: [
            Keys.otterEnabled: true,
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
            Keys.widthOffset: 0.0,
            Keys.dropOffset: 0.0,
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
        notchWidthOffset = defaults.double(forKey: Keys.widthOffset)
        expandedDropOffset = defaults.double(forKey: Keys.dropOffset)
        perScreenWidthOffset = defaults.dictionary(forKey: Keys.perScreenWidthOffset) as? [String: Double] ?? [:]
        perScreenDropOffset = defaults.dictionary(forKey: Keys.perScreenDropOffset) as? [String: Double] ?? [:]
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
        static let widthOffset = "notchWidthOffset"
        static let dropOffset = "expandedDropOffset"
        static let perScreenWidthOffset = "perScreenWidthOffset"
        static let perScreenDropOffset = "perScreenDropOffset"
    }
}
