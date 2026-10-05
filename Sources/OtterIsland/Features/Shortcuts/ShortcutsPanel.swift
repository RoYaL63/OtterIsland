import SwiftUI

/// Onglet « Raccourcis » de l'île : apps, dossiers, liens et raccourcis macOS
/// épinglés, à lancer en un clic. Et, si la barre des menus est pliée, de quoi
/// faire réapparaître les icônes cachées.
struct ShortcutsPanel: View {
    @ObservedObject var store: QuickShortcutStore
    @EnvironmentObject private var settings: OtterSettings
    let onOpenSettings: () -> Void
    let onToggleMenuBar: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OtterTile(horizontalPadding: 10, verticalPadding: 10) {
                if store.items.isEmpty {
                    VStack(spacing: 8) {
                        OtterEmptyState(
                            icon: "bolt.fill",
                            title: "Aucun raccourci",
                            subtitle: "Épingle des apps, des dossiers, des liens ou des raccourcis macOS."
                        )
                        OtterActionLink(title: "Ajouter des raccourcis", icon: "plus", tint: Otter.accent, action: onOpenSettings)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(store.items) { item in
                                ShortcutButton(item: item)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }

            HStack(spacing: 12) {
                if settings.menuBarManagerEnabled {
                    OtterActionLink(title: "Icônes de la barre", icon: "menubar.arrow.up.rectangle", tint: Otter.accent, action: onToggleMenuBar)
                        .help("Afficher ou cacher les icônes rangées à gauche du trait │")
                }
                Spacer(minLength: 0)
                OtterActionLink(title: "Gérer", icon: "slider.horizontal.3", action: onOpenSettings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Une case de la grille : icône et nom, survol, grisée si la cible a disparu.
private struct ShortcutButton: View {
    let item: QuickShortcut
    @State private var isHovering = false

    var body: some View {
        Button {
            item.open()
        } label: {
            VStack(spacing: 4) {
                icon
                    .frame(width: 30, height: 30)
                Text(item.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Otter.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous)
                    .fill(isHovering ? Otter.tileFillActive : .clear)
            )
            .opacity(item.isMissing ? 0.4 : 1)
        }
        .buttonStyle(OtterPressStyle(scale: 0.92))
        .disabled(item.isMissing)
        .onHover { hovering in withAnimation(Otter.hoverMotion) { isHovering = hovering } }
        .help(item.isMissing ? "\(item.title) est introuvable" : "\(item.kindLabel) : \(item.title)")
    }

    @ViewBuilder
    private var icon: some View {
        if let image = item.fileIcon {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Otter.textPrimary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Otter.chipFill))
        }
    }
}
