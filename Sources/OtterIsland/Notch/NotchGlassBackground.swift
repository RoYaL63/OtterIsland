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
    let bottomRadius: CGFloat
    let isExpanded: Bool

    var body: some View {
        Color.clear
            .liquidGlassBackground(
                in: NotchShape(bottomRadius: bottomRadius),
                tint: isExpanded ? .white.opacity(0.55) : .black.opacity(0.55)
            )
            .overlay(
                NotchShape(bottomRadius: bottomRadius)
                    .stroke(Color.white.opacity(isExpanded ? 0.5 : 0), lineWidth: 0.75)
            )
    }
}
