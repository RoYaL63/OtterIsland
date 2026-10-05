import AppKit
import Combine
import SwiftUI

/// Apparence personnalisable : couleur d'accent, teinte et opacité du verre,
/// type de matériau, contraste du texte. Persistée dans UserDefaults.
///
/// Un singleton plutôt qu'un objet d'environnement : la palette (`Otter.accent`,
/// `Otter.glassTint`…) est lue depuis des dizaines de vues par des propriétés
/// statiques. Elles lisent désormais ici ; l'île se reconstruit quand la
/// palette change (voir `revision`).
final class OtterAppearance: ObservableObject {
    nonisolated(unsafe) static let shared = OtterAppearance()

    /// Style d'ensemble. Les réglages fins (accent, teinte…) ne s'appliquent
    /// qu'en `custom`.
    enum Style: String, CaseIterable, Identifiable {
        /// Le style d'origine : verre sombre, accent aqua de l'icône.
        case otter
        /// Suit les Réglages Système › Apparence : mode clair / sombre,
        /// Liquid Glass transparent / teinté, couleur du thème. Aucune teinte
        /// ajoutée par l'app.
        case system
        /// Accent, teinte, opacité et matériau réglés à la main.
        case custom

        var id: String { rawValue }
        var title: String {
            switch self {
            case .otter: return "OtterIsland"
            case .system: return "Système"
            case .custom: return "Personnalisé"
            }
        }
        var detail: String {
            switch self {
            case .otter: return "Le style d'origine : verre sombre et accent aqua de l'icône."
            case .system: return "Suit Réglages Système › Apparence : mode clair ou sombre, Liquid Glass transparent ou teinté, couleur du thème. L'encoche repliée reste noire, comme l'encoche de l'écran."
            case .custom: return "Accent, teinte, opacité et matériau réglés ci-dessous."
            }
        }
    }

    /// Matériau des surfaces de premier niveau (île, HUD, aperçus).
    enum Material: String, CaseIterable, Identifiable {
        /// Liquid Glass de macOS 26 : le fond d'écran vit à travers.
        case liquid
        /// Verre dépoli classique : flou marqué, plus calme.
        case frosted
        /// Aplat de la teinte, sans transparence : le plus sobre.
        case solid

        var id: String { rawValue }
        var title: String {
            switch self {
            case .liquid: return "Liquid Glass"
            case .frosted: return "Verre dépoli"
            case .solid: return "Opaque"
            }
        }
    }

    /// Accents proposés. `system` suit la couleur d'accentuation de macOS
    /// (Réglages Système › Apparence).
    static let accentPresets: [(name: String, hex: String)] = [
        ("Aqua OtterIsland", Default.accentHex),
        ("Couleur du système", systemAccentToken),
        ("Graphite", "#A1A1A6"),
        ("Blanc", "#F2F2F7"),
        ("Bleu", "#4BA3FF"),
        ("Violet", "#A78BFA"),
        ("Rose", "#F472B6"),
        ("Orange", "#FB923C"),
        ("Vert", "#4ADE80"),
    ]

    static let tintPresets: [(name: String, hex: String)] = [
        ("Noir", "#000000"),
        ("Graphite", "#1C1C1E"),
        ("Bleu nuit", "#0B1630"),
        ("Brun", "#1F1611"),
    ]

    /// Valeur spéciale de `accentHex` : suivre l'accent de macOS.
    static let systemAccentToken = "system"

    enum Default {
        static let accentHex = "#5EE9D3"
        static let tintHex = "#000000"
        static let glassOpacity = 0.60
        static let readability = 1.0
        static let material = Material.liquid
        static let cornerRadius = 28.0
        static let shadow = 0.45
        static let rim = 1.0
        static let tileIntensity = 1.0
        static let accentGradient = true
    }

    @Published var style: Style { didSet { defaults.set(style.rawValue, forKey: Keys.style) } }
    @Published var accentHex: String { didSet { defaults.set(accentHex, forKey: Keys.accent) } }
    @Published var tintHex: String { didSet { defaults.set(tintHex, forKey: Keys.tint) } }
    /// Opacité de la teinte posée sur le verre. Plus haut = plus sombre et
    /// plus calme ; plus bas = le fond d'écran transparaît davantage.
    @Published var glassOpacity: Double { didSet { defaults.set(glassOpacity, forKey: Keys.opacity) } }
    /// Multiplicateur du voile de lisibilité sous le texte (1 = d'origine).
    @Published var readability: Double { didSet { defaults.set(readability, forKey: Keys.readability) } }
    @Published var material: Material { didSet { defaults.set(material.rawValue, forKey: Keys.material) } }

    // Réglages avancés (style Personnalisé)
    /// Arrondi des coins bas de l'île ouverte.
    @Published var cornerRadius: Double { didSet { defaults.set(cornerRadius, forKey: Keys.cornerRadius) } }
    /// Opacité de l'ombre portée sous l'île ouverte.
    @Published var shadow: Double { didSet { defaults.set(shadow, forKey: Keys.shadow) } }
    /// Intensité du liseré lumineux sur la tranche du verre.
    @Published var rim: Double { didSet { defaults.set(rim, forKey: Keys.rim) } }
    /// Multiplicateur du remplissage des tuiles et pastilles posées sur le verre.
    @Published var tileIntensity: Double { didSet { defaults.set(tileIntensity, forKey: Keys.tileIntensity) } }
    /// Accent en dégradé (reflet) ou en aplat.
    @Published var accentGradient: Bool { didSet { defaults.set(accentGradient, forKey: Keys.accentGradient) } }
    /// Préférence d'affichage : la page montre-t-elle les réglages avancés ?
    @Published var showAdvanced: Bool { didSet { defaults.set(showAdvanced, forKey: Keys.showAdvanced) } }

    /// Incrémenté (avec un léger délai) après tout changement. L'île s'en sert
    /// comme identité pour se reconstruire : sans ça, une vue qui lit
    /// `Otter.accent` sans rien observer garderait l'ancienne couleur.
    @Published private(set) var revision = 0

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let accent = defaults.string(forKey: Keys.accent) ?? Default.accentHex
        let tint = defaults.string(forKey: Keys.tint) ?? Default.tintHex
        let opacity = defaults.object(forKey: Keys.opacity) as? Double ?? Default.glassOpacity
        let readability = defaults.object(forKey: Keys.readability) as? Double ?? Default.readability
        let material = Material(rawValue: defaults.string(forKey: Keys.material) ?? "") ?? Default.material
        accentHex = accent
        tintHex = tint
        glassOpacity = opacity
        self.readability = readability
        self.material = material
        cornerRadius = defaults.object(forKey: Keys.cornerRadius) as? Double ?? Default.cornerRadius
        shadow = defaults.object(forKey: Keys.shadow) as? Double ?? Default.shadow
        rim = defaults.object(forKey: Keys.rim) as? Double ?? Default.rim
        tileIntensity = defaults.object(forKey: Keys.tileIntensity) as? Double ?? Default.tileIntensity
        accentGradient = defaults.object(forKey: Keys.accentGradient) as? Bool ?? Default.accentGradient
        showAdvanced = defaults.bool(forKey: Keys.showAdvanced)
        if let saved = Style(rawValue: defaults.string(forKey: Keys.style) ?? "") {
            style = saved
        } else {
            // Réglages faits en 1.3.0, avant l'arrivée des styles : on les garde.
            let customized = accent != Default.accentHex || tint != Default.tintHex
                || opacity != Default.glassOpacity || readability != Default.readability
                || material != Default.material
            style = customized ? .custom : .otter
        }

        let changes: [AnyPublisher<Void, Never>] = [
            $style.map { _ in () }.eraseToAnyPublisher(),
            $accentHex.map { _ in () }.eraseToAnyPublisher(),
            $tintHex.map { _ in () }.eraseToAnyPublisher(),
            $glassOpacity.map { _ in () }.eraseToAnyPublisher(),
            $readability.map { _ in () }.eraseToAnyPublisher(),
            $material.map { _ in () }.eraseToAnyPublisher(),
            $cornerRadius.map { _ in () }.eraseToAnyPublisher(),
            $shadow.map { _ in () }.eraseToAnyPublisher(),
            $rim.map { _ in () }.eraseToAnyPublisher(),
            $tileIntensity.map { _ in () }.eraseToAnyPublisher(),
            $accentGradient.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .dropFirst(changes.count) // valeurs initiales
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in self?.revision += 1 }
            .store(in: &cancellables)
    }

    func reset() {
        style = .otter
        accentHex = Default.accentHex
        tintHex = Default.tintHex
        glassOpacity = Default.glassOpacity
        readability = Default.readability
        material = Default.material
        resetAdvanced()
    }

    func resetAdvanced() {
        cornerRadius = Default.cornerRadius
        shadow = Default.shadow
        rim = Default.rim
        tileIntensity = Default.tileIntensity
        accentGradient = Default.accentGradient
    }

    // MARK: Valeurs effectives (selon le style)

    /// Style Système : couleurs de texte et de remplissage qui suivent le
    /// mode clair / sombre au lieu du blanc fixe pensé pour le verre sombre.
    var adaptive: Bool { style == .system }

    var accent: Color {
        switch style {
        case .otter: return Color(hex: Default.accentHex, fallback: .teal)
        case .system: return Color(nsColor: .controlAccentColor)
        case .custom:
            return accentHex == Self.systemAccentToken
                ? Color(nsColor: .controlAccentColor)
                : Color(hex: accentHex, fallback: Color(hex: Default.accentHex))
        }
    }

    /// Deuxième teinte du dégradé d'accent. Pour l'aqua d'origine, le cyan de
    /// l'icône ; pour tout autre accent, la même couleur un cran plus sombre.
    var accentDeep: Color {
        if style == .otter || (style == .custom && accentHex.caseInsensitiveCompare(Default.accentHex) == .orderedSame) {
            return Color(red: 0.231, green: 0.792, blue: 0.910)
        }
        let base = NSColor(accent).usingColorSpace(.sRGB) ?? .systemTeal
        return Color(nsColor: base.blended(withFraction: 0.22, of: .black) ?? base)
    }

    /// Texte ou icône posé SUR l'accent : sombre sur un accent clair (aqua,
    /// blanc), blanc sur un accent soutenu (bleu système, violet).
    var onAccent: Color {
        guard let c = NSColor(accent).usingColorSpace(.sRGB) else { return .black.opacity(0.8) }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.55 ? .black.opacity(0.8) : .white
    }

    var tint: Color { Color(hex: tintHex, fallback: .black) }

    /// Teinte posée sur le verre. Aucune en style Système : c'est macOS qui
    /// décide (Liquid Glass transparent ou teinté).
    var glassTint: Color {
        switch style {
        case .otter: return Color.black.opacity(Default.glassOpacity)
        case .system: return .clear
        case .custom: return tint.opacity(glassOpacity)
        }
    }

    var effectiveMaterial: Material { style == .custom ? material : .liquid }

    /// Voile de lisibilité. Aucun en style Système : le texte suit déjà le mode
    /// clair / sombre, un voile noir griserait le verre clair.
    var effectiveReadability: Double {
        switch style {
        case .otter: return Default.readability
        case .system: return 0
        case .custom: return readability
        }
    }

    // Avancés : effectifs en style Personnalisé seulement, valeurs d'origine sinon.
    private var custom: Bool { style == .custom }
    var effectiveCornerRadius: Double { custom ? cornerRadius : Default.cornerRadius }
    var effectiveShadow: Double { custom ? shadow : Default.shadow }
    var effectiveRim: Double { custom ? rim : Default.rim }
    var effectiveTileIntensity: Double { custom ? tileIntensity : Default.tileIntensity }
    var effectiveAccentGradient: Bool { custom ? accentGradient : Default.accentGradient }

    private enum Keys {
        static let style = "appearanceStyle"
        static let cornerRadius = "appearanceCornerRadius"
        static let shadow = "appearanceShadow"
        static let rim = "appearanceRim"
        static let tileIntensity = "appearanceTileIntensity"
        static let accentGradient = "appearanceAccentGradient"
        static let showAdvanced = "appearanceShowAdvanced"
        static let accent = "appearanceAccentHex"
        static let tint = "appearanceTintHex"
        static let opacity = "appearanceGlassOpacity"
        static let readability = "appearanceReadability"
        static let material = "appearanceMaterial"
    }
}
