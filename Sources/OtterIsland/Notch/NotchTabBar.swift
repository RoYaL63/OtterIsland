import SwiftUI

/// Barre d'onglets de la carte étendue : une pastille aqua qui GLISSE d'un
/// onglet à l'autre, dans un rail discret.
///
/// Avant : sept icônes de 30 pt flottant côte à côte sans contenant, dont seule
/// la sélectionnée avait un fond — la barre ne se lisait pas comme un objet, et
/// le changement d'onglet était un saut sec. Le rail donne un début et une fin
/// au groupe, `matchedGeometryEffect` fait voyager l'indicateur, et l'ensemble
/// est plus compact (200 pt au lieu de 246) : autant de rendu au contenu.
struct NotchTabBar: View {
    @Binding var selection: NotchTab

    @Namespace private var indicator
    @State private var hovered: NotchTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .foregroundStyle(tint(for: tab))
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(Otter.accent)
                                    .matchedGeometryEffect(id: "selection", in: indicator)
                            } else if hovered == tab {
                                Capsule().fill(Color.white.opacity(0.12))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        if hovering {
                            hovered = tab
                        } else if hovered == tab {
                            hovered = nil
                        }
                    }
                }
                .help(tab.title)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.07))
                .overlay(Capsule().stroke(Otter.chipStroke, lineWidth: 0.5))
        )
    }

    /// Icône sombre sur la pastille aqua (du blanc sur aqua serait illisible),
    /// blanc franc au survol, gris en veille.
    private func tint(for tab: NotchTab) -> Color {
        if selection == tab { return .black.opacity(0.78) }
        return hovered == tab ? Otter.textPrimary : Otter.textSecondary
    }
}
