import SwiftUI

/// Barre d'onglets de la carte étendue : une pastille aqua qui GLISSE d'un
/// onglet à l'autre, dans un rail de verre.
///
/// Avant : sept icônes de 30 pt flottant côte à côte sans contenant, dont seule
/// la sélectionnée avait un fond — la barre ne se lisait pas comme un objet, et
/// le changement d'onglet était un saut sec. Le rail donne un début et une fin
/// au groupe, `matchedGeometryEffect` fait voyager l'indicateur.
///
/// L'indicateur est dégradé et bordé de son liseré, comme le pouce d'un
/// contrôle segmenté du système : un aplat de couleur reste plat, une pastille
/// qui attrape la lumière a l'air posée SUR le verre.
struct NotchTabBar: View {
    @Binding var selection: NotchTab
    /// Onglets affichés et leur ordre : Réglages › Fonctionnalités.
    @EnvironmentObject private var settings: OtterSettings

    @Namespace private var indicator
    @State private var hovered: NotchTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(settings.visibleTabs) { tab in
                Button {
                    withAnimation(Otter.selectionMotion) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 27, height: 24)
                        .foregroundStyle(tint(for: tab))
                        .background {
                            if selection == tab {
                                ZStack {
                                    Capsule().fill(Otter.accentGradient)
                                    SpecularRim(shape: Capsule(), strength: 0.9, lineWidth: 0.75)
                                }
                                // Halo court : la pastille active éclaire le
                                // verre autour d'elle au lieu d'y être posée à plat.
                                .shadow(color: Otter.accent.opacity(0.3), radius: 5, y: 1)
                                .matchedGeometryEffect(id: "selection", in: indicator)
                            } else if hovered == tab {
                                Capsule().fill(Otter.tileFillActive)
                            }
                        }
                        .contentShape(Rectangle())
                }
                // Le retour part à l'appui, pas au relâchement : sans lui, il ne
                // se passe rien entre le clic et le glissement de la pastille.
                .buttonStyle(OtterPressStyle(scale: 0.9))
                .onHover { hovering in
                    withAnimation(Otter.hoverMotion) {
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
        .background {
            ZStack {
                Capsule().fill(Otter.ink(0.06))
                SpecularRim(shape: Capsule(), strength: 0.5, lineWidth: 0.75)
            }
        }
    }

    /// Icône contrastée sur la pastille d'accent (sombre sur l'aqua, blanche
    /// sur un accent soutenu), franche au survol, en retrait en veille.
    private func tint(for tab: NotchTab) -> Color {
        if selection == tab { return Otter.onAccent }
        return hovered == tab ? Otter.textPrimary : Otter.textSecondary
    }
}
