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
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .modifier(SelectedTabBackground(isSelected: selection == tab))
                        .foregroundStyle(selection == tab ? .white : .white.opacity(0.5))
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
            content.liquidGlassBackground(in: Circle(), tint: .white.opacity(0.3))
        } else {
            content
        }
    }
}
