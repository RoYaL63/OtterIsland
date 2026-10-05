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
    }

    @Published var accentHex: String { didSet { defaults.set(accentHex, forKey: Keys.accent) } }
    @Published var tintHex: String { didSet { defaults.set(tintHex, forKey: Keys.tint) } }
    /// Opacité de la teinte posée sur le verre. Plus haut = plus sombre et
    /// plus calme ; plus bas = le fond d'écran transparaît davantage.
    @Published var glassOpacity: Double { didSet { defaults.set(glassOpacity, forKey: Keys.opacity) } }
    /// Multiplicateur du voile de lisibilité sous le texte (1 = d'origine).
    @Published var readability: Double { didSet { defaults.set(readability, forKey: Keys.readability) } }
    @Published var material: Material { didSet { defaults.set(material.rawValue, forKey: Keys.material) } }

    /// Incrémenté (avec un léger délai) après tout changement. L'île s'en sert
    /// comme identité pour se reconstruire : sans ça, une vue qui lit
    /// `Otter.accent` sans rien observer garderait l'ancienne couleur.
    @Published private(set) var revision = 0

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private init() {
        accentHex = defaults.string(forKey: Keys.accent) ?? Default.accentHex
        tintHex = defaults.string(forKey: Keys.tint) ?? Default.tintHex
        glassOpacity = defaults.object(forKey: Keys.opacity) as? Double ?? Default.glassOpacity
        readability = defaults.object(forKey: Keys.readability) as? Double ?? Default.readability
        material = Material(rawValue: defaults.string(forKey: Keys.material) ?? "") ?? Default.material

        let changes: [AnyPublisher<Void, Never>] = [
            $accentHex.map { _ in () }.eraseToAnyPublisher(),
            $tintHex.map { _ in () }.eraseToAnyPublisher(),
            $glassOpacity.map { _ in () }.eraseToAnyPublisher(),
            $readability.map { _ in () }.eraseToAnyPublisher(),
            $material.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .dropFirst(changes.count) // valeurs initiales
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in self?.revision += 1 }
            .store(in: &cancellables)
    }

    func reset() {
        accentHex = Default.accentHex
        tintHex = Default.tintHex
        glassOpacity = Default.glassOpacity
        readability = Default.readability
        material = Default.material
    }

    // MARK: Couleurs calculées

    var accent: Color {
        accentHex == Self.systemAccentToken
            ? Color(nsColor: .controlAccentColor)
            : Color(hex: accentHex, fallback: Color(hex: Default.accentHex))
    }

    /// Deuxième teinte du dégradé d'accent. Pour l'aqua d'origine, le cyan de
    /// l'icône ; pour tout autre accent, la même couleur un cran plus sombre.
    var accentDeep: Color {
        if accentHex.caseInsensitiveCompare(Default.accentHex) == .orderedSame {
            return Color(red: 0.231, green: 0.792, blue: 0.910)
        }
        let base = NSColor(accent).usingColorSpace(.sRGB) ?? .systemTeal
        return Color(nsColor: base.blended(withFraction: 0.22, of: .black) ?? base)
    }

    var tint: Color { Color(hex: tintHex, fallback: .black) }

    var glassTint: Color { tint.opacity(glassOpacity) }

    private enum Keys {
        static let accent = "appearanceAccentHex"
        static let tint = "appearanceTintHex"
        static let opacity = "appearanceGlassOpacity"
        static let readability = "appearanceReadability"
        static let material = "appearanceMaterial"
    }
}
