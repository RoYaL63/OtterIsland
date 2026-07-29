import SwiftUI

/// Fond de l'encoche : Liquid Glass natif sur macOS 26+, repli en matériau
/// translucide sur les systèmes plus anciens (le projet cible macOS 14+).
struct NotchGlassBackground: View {
    let bottomRadius: CGFloat
    /// Plus opaque une fois agrandie : la carte contient du texte, le verre
    /// pur laissait trop passer le fond d'écran et nuisait à la lisibilité.
    let isExpanded: Bool

    var body: some View {
        Color.clear
            .liquidGlassBackground(
                in: NotchShape(bottomRadius: bottomRadius),
                tint: .black.opacity(isExpanded ? 0.85 : 0.55)
            )
    }
}
