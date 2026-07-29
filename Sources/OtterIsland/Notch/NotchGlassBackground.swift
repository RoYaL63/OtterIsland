import SwiftUI

/// Fond de l'encoche : Liquid Glass natif (macOS 26+) avec une teinte sombre
/// très opaque — garde les reflets/animations fluides du vrai matériau verre
/// tout en restant assez opaque pour un fort contraste avec le texte blanc
/// (un premier essai en teinte CLAIRE façon Centre de contrôle était trop
/// transparent en pratique ; un repli en noir plein sans glass perdait les
/// animations. Ceci garde les deux : contraste fort + reflets fluides).
///
/// Par-dessus le matériau, un liseré lumineux dégradé (blanc → transparent,
/// du haut vers le bas) souligne la tranche du verre quand la carte est
/// dépliée — c'est lui qui donne l'épaisseur « goutte d'eau » au bord.
/// Replié, il s'éteint : rien ne doit briller sur l'encoche physique.
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

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Color.black.opacity(0.96))
            } else {
                Color.clear
                    .liquidGlassBackground(in: shape, tint: .black.opacity(0.85))
                    // Voile de lisibilité PAR-DESSUS le verre : le glass adaptatif
                    // s'éclaircit selon ce qui passe derrière l'encoche (doc Apple),
                    // donc la teinte seule ne garantit rien — ce scrim fixe un
                    // plancher d'obscurité constant sous le texte blanc, en
                    // laissant les reflets liquides vivre sur les bords.
                    .overlay(shape.fill(Color.black.opacity(0.4)))
            }
        }
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(isExpanded ? 0.25 : 0),
                                .white.opacity(isExpanded ? 0.07 : 0),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
    }
}
