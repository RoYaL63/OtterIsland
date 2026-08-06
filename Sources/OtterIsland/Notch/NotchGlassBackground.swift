import SwiftUI

/// Fond de l'encoche : Liquid Glass natif (macOS 26+), teinté sombre.
///
/// La teinte est volontairement plus légère qu'avant (0,60 + un voile dégradé,
/// contre 0,85 + un voile plat) : le matériau ne se lit comme du VERRE que si
/// le fond d'écran continue de vivre à travers. Le contraste du texte blanc est
/// tenu par le voile, dégradé du haut (sous l'encoche physique, là où tombent
/// les titres) vers le bas, plutôt que par un aplat noir qui éteignait le
/// matériau et transformait l'île en rectangle opaque.
///
/// Par-dessus, le liseré spéculaire partagé (`SpecularRim`) donne la tranche
/// « goutte d'eau » quand la carte est dépliée. Replié, il s'atténue : rien ne
/// doit briller sur l'encoche physique.
struct NotchGlassBackground: View {
    /// Largeur réelle de l'encoche physique (nil si le Mac n'en a pas).
    let topWidth: CGFloat?
    /// Hauteur du nub du haut avant évasement (= hauteur de l'encoche/barre de menus).
    let topHeight: CGFloat
    let bottomRadius: CGFloat
    let isExpanded: Bool

    /// « Réduire la transparence » (doc Adopting Liquid Glass) : repli en noir
    /// quasi opaque, sans matériau.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: NotchShape {
        NotchShape(topWidth: topWidth, topHeight: topHeight, bottomRadius: bottomRadius)
    }

    /// Plancher de lisibilité. Le verre adaptatif s'éclaircit selon ce qui passe
    /// derrière l'encoche (doc Apple) : la teinte seule ne garantit rien, ce
    /// voile fixe un minimum d'obscurité sous le texte — plus dense en haut,
    /// presque effacé en bas où le verre peut respirer.
    private var scrim: LinearGradient {
        LinearGradient(
            colors: [
                .black.opacity(isExpanded ? 0.30 : 0.36),
                .black.opacity(isExpanded ? 0.16 : 0.30),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Color.black.opacity(0.96))
            } else {
                Color.clear
                    .liquidGlassBackground(in: shape, tint: Otter.glassTint)
                    .overlay(shape.fill(scrim))
            }
        }
        .overlay(SpecularRim(shape: shape, strength: isExpanded ? 1 : 0))
    }
}
