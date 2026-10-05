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

    /// Nombre de cases disponibles (onglets + flèches), calculé par l'île
    /// selon la place restante. Au-delà, les onglets passent sur une page
    /// suivante, atteinte par une flèche ›.
    var maxSlots: Int = .max

    @Namespace private var indicator
    @State private var hovered: NotchTab?
    @State private var page = 0

    /// Largeur d'une case : 27 pt de bouton + 2 pt d'espacement.
    static let slotWidth: CGFloat = 29
    /// Marges intérieures du rail.
    static let railPadding: CGFloat = 6

    /// Découpe en pages : chacune garde une case pour ‹ (sauf la première)
    /// et une pour › (sauf la dernière). Si tout tient, une seule page.
    private var pages: [[NotchTab]] {
        let tabs = settings.visibleTabs
        let slots = max(3, maxSlots)
        guard tabs.count > slots else { return [tabs] }
        var result: [[NotchTab]] = []
        var start = 0
        while start < tabs.count {
            let hasLeft = !result.isEmpty
            let remaining = tabs.count - start
            // Dernière page : plus besoin de flèche ›.
            let capacityIfLast = slots - (hasLeft ? 1 : 0)
            let take = remaining <= capacityIfLast ? remaining : slots - (hasLeft ? 1 : 0) - 1
            result.append(Array(tabs[start..<start + take]))
            start += take
        }
        return result
    }

    private var currentPage: Int { min(page, pages.count - 1) }

    var body: some View {
        let pages = self.pages
        HStack(spacing: 2) {
            if currentPage > 0 {
                pageArrow("chevron.left", help: "Onglets précédents") { page = currentPage - 1 }
            }
            ForEach(pages[currentPage]) { tab in
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
            if currentPage < pages.count - 1 {
                pageArrow("chevron.right", help: "Plus d'onglets") { page = currentPage + 1 }
            }
        }
        .padding(3)
        // Onglet choisi ailleurs (raccourci ⌥V, fichier déposé…) : on affiche
        // la page qui le contient.
        .onChange(of: selection) { _, tab in
            if let index = pages.firstIndex(where: { $0.contains(tab) }) {
                withAnimation(Otter.selectionMotion) { page = index }
            }
        }
        .background {
            ZStack {
                Capsule().fill(Otter.ink(0.06))
                SpecularRim(shape: Capsule(), strength: 0.5, lineWidth: 0.75)
            }
        }
    }

    private func pageArrow(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Otter.selectionMotion, action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 27, height: 24)
                .foregroundStyle(Otter.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(OtterPressStyle(scale: 0.9))
        .help(help)
    }

    /// Icône contrastée sur la pastille d'accent (sombre sur l'aqua, blanche
    /// sur un accent soutenu), franche au survol, en retrait en veille.
    private func tint(for tab: NotchTab) -> Color {
        if selection == tab { return Otter.onAccent }
        return hovered == tab ? Otter.textPrimary : Otter.textSecondary
    }
}
