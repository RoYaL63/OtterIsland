import SwiftUI

/// Barre d'onglets compacte en haut à droite de la carte étendue.
struct NotchTabBar: View {
    @Binding var selection: NotchTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = tab }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .modifier(SelectedTabBackground(isSelected: selection == tab))
                        // Actif : pastille blanche + icône sombre (comme un toggle
                        // allumé du Centre de contrôle) — blanc-sur-gris illisible.
                        .foregroundStyle(selection == tab ? Color.black.opacity(0.8) : Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }
}

private struct SelectedTabBackground: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.liquidGlassBackground(in: Circle(), tint: .white.opacity(0.9))
        } else {
            content
        }
    }
}
