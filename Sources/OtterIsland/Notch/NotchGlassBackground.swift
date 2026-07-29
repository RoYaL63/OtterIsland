import SwiftUI

/// Fond de l'encoche : Liquid Glass natif sur macOS 26+, repli en matériau
/// translucide sur les systèmes plus anciens (le projet cible macOS 14+).
struct NotchGlassBackground: View {
    let bottomRadius: CGFloat

    var body: some View {
        Color.clear
            .liquidGlassBackground(in: NotchShape(bottomRadius: bottomRadius))
    }
}
