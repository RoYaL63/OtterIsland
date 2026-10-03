import AppKit
import SwiftUI

/// Outils de dessin du mode Live.
enum LiveTool: String, CaseIterable, Identifiable, Codable {
    case pen, arrow, rectangle, ellipse, marker, laser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "Stylo"
        case .arrow: return "Flèche"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Cercle"
        case .marker: return "Surligneur"
        case .laser: return "Laser"
        }
    }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .marker: return "highlighter"
        case .laser: return "light.max"
        }
    }

    /// Lettre du raccourci global ⌃⌥ + lettre.
    var shortcutLetter: String {
        switch self {
        case .pen: return "P"
        case .arrow: return "F"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .marker: return "S"
        case .laser: return "L"
        }
    }
}

/// Effet qui accompagne le curseur pendant le Live.
enum LiveCursorEffect: String, CaseIterable, Identifiable, Codable {
    case none, halo, meteor, otterRiver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Aucun"
        case .halo: return "Halo"
        case .meteor: return "Météorite"
        case .otterRiver: return "Rivière loutre"
        }
    }

    var detail: String {
        switch self {
        case .none: return "Le curseur reste tel quel."
        case .halo: return "Un anneau lumineux suit le curseur."
        case .meteor: return "Une traînée de feu qui s'allonge avec la vitesse du geste."
        case .otterRiver: return "Un ruban d'eau ondulant, des bulles et une petite loutre."
        }
    }
}

/// Touche à maintenir pour dessiner sans passer par le mode stylo.
enum LiveDrawModifier: String, CaseIterable, Identifiable, Codable {
    case control, option, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .control: return "⌃ Contrôle"
        case .option: return "⌥ Option"
        case .none: return "Désactivé"
        }
    }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .control: return .control
        case .option: return .option
        case .none: return nil
        }
    }
}

enum LiveKeysPosition: String, CaseIterable, Identifiable, Codable {
    case bottom, top
    var id: String { rawValue }
    var title: String { self == .bottom ? "En bas" : "En haut" }
}

/// Préférences du mode Live, enregistrées d'un bloc en JSON dans UserDefaults.
/// Un seul objet plutôt que quinze clés : le panneau de personnalisation les
/// modifie toutes, et elles voyagent ensemble.
struct LivePreferences: Codable, Equatable {
    /// Couleurs proposées dans l'island (les 5 premières) et le panneau.
    var palette: [String] = ["#FF453A", "#FFD60A", "#5EE9D3", "#0A84FF", "#FFFFFF", "#BF5AF2", "#FF9F0A", "#30D158"]
    var colorHex: String = "#FF453A"
    var strokeWidth: Double = 4
    /// Secondes avant le fondu. 0 = les dessins restent jusqu'à effacement.
    var fadeSeconds: Double = 8
    var glow: Bool = true
    var straightenShapes: Bool = true

    var cursorEffect: LiveCursorEffect = .meteor
    var cursorEffectHex: String = "#FFB340"
    var cursorEffectSize: Double = 1
    var clickRipples: Bool = true

    var spotlightRadius: Double = 120
    var spotlightDarkness: Double = 0.6

    var showKeys: Bool = true
    var keysPosition: LiveKeysPosition = .bottom
    var keysScale: Double = 1

    var maskSecrets: Bool = true
    var maskApps: Bool = true
    var maskedBundleIDs: [String] = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess",
        "com.apple.Passwords", "com.bitwarden.desktop", "com.apple.MobileSMS",
    ]
    /// Lance les raccourcis Concentration du Pomodoro au début et à la fin du Live.
    var focusDuringLive: Bool = true

    var drawModifier: LiveDrawModifier = .control

    init() {}

    /// Décodage tolérant : une clé absente (réglage ajouté dans une version
    /// plus récente) prend sa valeur par défaut au lieu de faire échouer tout
    /// le décodage — et de remettre à zéro les couleurs de l'utilisateur.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LivePreferences()
        palette = (try? c.decode([String].self, forKey: .palette)) ?? d.palette
        colorHex = (try? c.decode(String.self, forKey: .colorHex)) ?? d.colorHex
        strokeWidth = (try? c.decode(Double.self, forKey: .strokeWidth)) ?? d.strokeWidth
        fadeSeconds = (try? c.decode(Double.self, forKey: .fadeSeconds)) ?? d.fadeSeconds
        glow = (try? c.decode(Bool.self, forKey: .glow)) ?? d.glow
        straightenShapes = (try? c.decode(Bool.self, forKey: .straightenShapes)) ?? d.straightenShapes
        cursorEffect = (try? c.decode(LiveCursorEffect.self, forKey: .cursorEffect)) ?? d.cursorEffect
        cursorEffectHex = (try? c.decode(String.self, forKey: .cursorEffectHex)) ?? d.cursorEffectHex
        cursorEffectSize = (try? c.decode(Double.self, forKey: .cursorEffectSize)) ?? d.cursorEffectSize
        clickRipples = (try? c.decode(Bool.self, forKey: .clickRipples)) ?? d.clickRipples
        spotlightRadius = (try? c.decode(Double.self, forKey: .spotlightRadius)) ?? d.spotlightRadius
        spotlightDarkness = (try? c.decode(Double.self, forKey: .spotlightDarkness)) ?? d.spotlightDarkness
        showKeys = (try? c.decode(Bool.self, forKey: .showKeys)) ?? d.showKeys
        keysPosition = (try? c.decode(LiveKeysPosition.self, forKey: .keysPosition)) ?? d.keysPosition
        keysScale = (try? c.decode(Double.self, forKey: .keysScale)) ?? d.keysScale
        maskSecrets = (try? c.decode(Bool.self, forKey: .maskSecrets)) ?? d.maskSecrets
        maskApps = (try? c.decode(Bool.self, forKey: .maskApps)) ?? d.maskApps
        maskedBundleIDs = (try? c.decode([String].self, forKey: .maskedBundleIDs)) ?? d.maskedBundleIDs
        focusDuringLive = (try? c.decode(Bool.self, forKey: .focusDuringLive)) ?? d.focusDuringLive
        drawModifier = (try? c.decode(LiveDrawModifier.self, forKey: .drawModifier)) ?? d.drawModifier
    }
}

/// Source de vérité observable des préférences.
@MainActor
final class LiveStyle: ObservableObject {
    @Published var prefs: LivePreferences {
        didSet { save() }
    }

    private static let key = "livePreferences"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LivePreferences.self, from: data) {
            prefs = decoded
        } else {
            prefs = LivePreferences()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func resetToDefaults() {
        prefs = LivePreferences()
    }

    var color: NSColor { NSColor(hex: prefs.colorHex) ?? .systemRed }
    var effectColor: NSColor { NSColor(hex: prefs.cursorEffectHex) ?? .systemOrange }

    /// Ajoute une couleur à la palette (en tête) et la sélectionne.
    func addToPalette(_ hex: String) {
        guard let normalized = NSColor.normalizedHex(hex) else { return }
        var palette = prefs.palette.filter { $0.uppercased() != normalized }
        palette.insert(normalized, at: 0)
        prefs.palette = Array(palette.prefix(16))
        prefs.colorHex = normalized
    }
}

// MARK: - Couleurs hexadécimales

extension NSColor {
    /// « #FF453A », « ff453a » ou « #F43 ». nil si la chaîne n'est pas une couleur.
    convenience init?(hex: String) {
        guard let normalized = NSColor.normalizedHex(hex) else { return nil }
        let value = UInt32(normalized.dropFirst(), radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Forme canonique « #RRGGBB » en majuscules, ou nil.
    static func normalizedHex(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + s
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension Color {
    init(hex: String, fallback: Color = .red) {
        if let ns = NSColor(hex: hex) { self.init(nsColor: ns) } else { self = fallback }
    }
}
