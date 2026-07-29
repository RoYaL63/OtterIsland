import SwiftUI
import Combine

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

    /// Utilise Cmd+V au lieu de Cmd+Shift+V pour ouvrir le presse-papier.
    /// Attention : écrase le collage système. Nécessite un redémarrage de l'app.
    @Published var clipboardUseCmdV: Bool {
        didSet { defaults.set(clipboardUseCmdV, forKey: Keys.clipboardUseCmdV) }
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
            Keys.clipboardUseCmdV: false,
            Keys.widthOffset: 0.0,
            Keys.dropOffset: 0.0,
        ])
        otterEnabled = defaults.bool(forKey: Keys.otterEnabled)
        showBattery = defaults.bool(forKey: Keys.showBattery)
        claudeCodeInboxEnabled = defaults.bool(forKey: Keys.claudeInbox)
        musicFollow = defaults.bool(forKey: Keys.musicFollow)
        gestureControl = defaults.bool(forKey: Keys.gestureControl)
        clipboardEnabled = defaults.bool(forKey: Keys.clipboardEnabled)
        clipboardUseCmdV = defaults.bool(forKey: Keys.clipboardUseCmdV)
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
        static let clipboardUseCmdV = "clipboardUseCmdV"
        static let widthOffset = "notchWidthOffset"
        static let dropOffset = "expandedDropOffset"
        static let perScreenWidthOffset = "perScreenWidthOffset"
        static let perScreenDropOffset = "perScreenDropOffset"
    }
}
