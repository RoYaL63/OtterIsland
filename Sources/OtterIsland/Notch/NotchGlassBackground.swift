import SwiftUI

/// Fond de l'encoche : noir plein et opaque, repliée comme agrandie — comme
/// TheBoringNotch et les autres apps d'encoche établies (`background(.black)`,
/// jamais de verre translucide sur la carte principale). Un essai de "liquid
/// glass" clair façon Centre de contrôle a été tenté puis abandonné : trop
/// transparent en pratique (on voyait le bureau/les fenêtres derrière), donc
/// illisible malgré le texte sombre. Le noir plein règle ça définitivement.
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
        shape.fill(Color.black)
    }
}
