import SwiftUI

/// Fond de l'encoche : Liquid Glass natif (macOS 26+) avec une teinte sombre
/// très opaque — garde les reflets/animations fluides du vrai matériau verre
/// tout en restant assez opaque pour un fort contraste avec le texte blanc
/// (un premier essai en teinte CLAIRE façon Centre de contrôle était trop
/// transparent en pratique ; un repli en noir plein sans glass perdait les
/// animations. Ceci garde les deux : contraste fort + reflets fluides).
struct NotchGlassBackground: View {
    /// Largeur réelle de l'encoche physique (nil si le Mac n'en a pas).
    let topWidth: CGFloat?
    /// Hauteur du nub du haut avant évasement (= hauteur de l'encoche/barre de menus).
    let topHeight: CGFloat
    let bottomRadius: CGFloat
    let isExpanded: Bool

    private var shape: NotchShape {
        NotchShape(topWidth: topWidth, topHeight: topHeight, bottomRadius: bottomRadius)
    }

    var body: some View {
        Color.clear
            .liquidGlassBackground(in: shape, tint: .black.opacity(0.92))
    }
}
