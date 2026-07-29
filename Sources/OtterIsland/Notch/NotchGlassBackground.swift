import SwiftUI

/// Fond de l'encoche : Liquid Glass natif sur macOS 26+, repli en matériau
/// translucide sur les systèmes plus anciens (le projet cible macOS 14+).
///
/// Repliée : reste sombre pour se fondre avec l'encoche physique du Mac (pas
/// de texte dessus). Agrandie : verre clair façon Centre de contrôle macOS —
/// le fond sombre + texte blanc d'origine était peu lisible sur fond d'écran
/// clair ; le Centre de contrôle d'Apple utilise justement un verre clair
/// avec du texte sombre, quel que soit le fond derrière.
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
            .liquidGlassBackground(
                in: shape,
                tint: isExpanded ? .white.opacity(0.55) : .black.opacity(0.55)
            )
            .overlay(
                shape.stroke(Color.white.opacity(isExpanded ? 0.5 : 0), lineWidth: 0.75)
            )
    }
}
