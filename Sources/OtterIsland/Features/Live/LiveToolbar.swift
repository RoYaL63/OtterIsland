import SwiftUI

/// Barre d'outils du Live dans l'island dépliée. Volontairement réduite :
/// outils, aides, cinq couleurs, durée. Le reste est dans « Personnaliser ».
/// Chaque bouton porte la lettre de son raccourci ⌃⌥ : on apprend les
/// raccourcis en se servant de la barre.
struct LiveToolbar: View {
    @ObservedObject var live: LiveController
    @ObservedObject var style: LiveStyle

    var body: some View {
        // Infos et personnalisation en haut, boutons-raccourcis sur le bord
        // bas : la rangée d'outils est celle qu'on vise sans regarder, elle
        // garde une place fixe au bord de l'île.
        VStack(alignment: .leading, spacing: 8) {
            Text(hint)
                .font(.otterMicro)
                .foregroundStyle(Otter.textTertiary)
                .lineLimit(1)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(Array(style.prefs.palette.prefix(5)), id: \.self) { hex in
                        swatch(hex)
                    }
                    if !style.prefs.palette.prefix(5).contains(where: { $0.uppercased() == style.prefs.colorHex.uppercased() }) {
                        swatch(style.prefs.colorHex)
                    }
                }

                Menu {
                    ForEach([3.0, 5.0, 8.0, 10.0, 20.0, 0.0], id: \.self) { seconds in
                        Button(seconds == 0 ? "Jamais (📌)" : "\(Int(seconds)) s") {
                            style.prefs.fadeSeconds = seconds
                        }
                    }
                } label: {
                    Label(style.prefs.fadeSeconds == 0 ? "Restent" : "\(Int(style.prefs.fadeSeconds)) s", systemImage: "timer")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Durée avant que les dessins s'estompent")

                Spacer(minLength: 4)

                OtterActionLink(title: "Personnaliser", icon: "slider.horizontal.3", tint: Otter.textSecondary) {
                    live.openCustomization()
                }
                Button {
                    live.stop()
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("Arrêter").font(.system(size: 10.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.58))
                    .background(Capsule().fill(Color.red.opacity(0.18)))
                }
                .buttonStyle(OtterPressStyle(scale: 0.95))
                .help("Arrêter le Live (⌃⌥L)")
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                group {
                    ForEach(LiveTool.allCases) { tool in
                        button(icon: tool.icon, title: tool.title, letter: tool.shortcutLetter, isOn: live.tool == tool, filled: true) {
                            live.select(tool)
                        }
                    }
                }
                group {
                    button(icon: effectIcon, title: "Effet de curseur : \(style.prefs.cursorEffect.title)", letter: "H", isOn: live.cursorEffectOn && style.prefs.cursorEffect != .none) {
                        live.toggleCursorEffect()
                    }
                    button(icon: "flashlight.on.fill", title: "Projecteur", letter: "B", isOn: live.spotlightOn) {
                        live.toggleSpotlight()
                    }
                    button(icon: "keyboard", title: "Touches affichées", letter: "K", isOn: live.keysOn) {
                        live.toggleKeys()
                    }
                    button(icon: "lock.shield", title: "Masquer clés et apps sensibles", letter: "M", isOn: live.maskingOn) {
                        live.toggleMasking()
                    }
                    button(icon: "plus.magnifyingglass", title: "Loupe macOS (⌥⌘8)", letter: nil, isOn: false) {
                        live.toggleSystemZoom()
                    }
                }
                group {
                    button(icon: "arrow.uturn.backward", title: "Annuler le dernier dessin", letter: "Z", isOn: false) {
                        live.undo()
                    }
                    .disabled(!live.hasDrawings)
                    button(icon: "trash", title: "Tout effacer", letter: "X", isOn: false) {
                        live.clearAll()
                    }
                    .disabled(!live.hasDrawings)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var hint: String {
        if live.tool != nil {
            return "Mode \(live.tool?.title.lowercased() ?? "stylo") · clic sur un dessin pour l'effacer · esc tout effacer · ⌃⌥Z annuler"
        }
        let modifier = style.prefs.drawModifier
        let draw = modifier == .none ? "" : "Maintiens \(modifier.title.prefix(1)) et glisse pour dessiner · "
        if !live.failedShortcuts.isEmpty {
            return draw + "Certains raccourcis ⌃⌥ sont pris par une autre app (barrés) · ⌃⌥L arrête le Live"
        }
        return draw + "Raccourcis : ⌃⌥ + la lettre (⌃⌥B projecteur…) · ⌃⌥L arrête le Live"
    }

    private func shortcutFailed(_ letter: String) -> Bool {
        LiveController.shortcuts.contains { $0.letter == letter && live.failedShortcuts.contains($0.id) }
    }

    private var effectIcon: String {
        switch style.prefs.cursorEffect {
        case .none, .halo: return "circle.dashed"
        case .meteor: return "wand.and.rays"
        case .sparkles: return "sparkles"
        case .dots: return "circle.grid.cross"
        }
    }

    // MARK: Composants

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func button(icon: String, title: String, letter: String?, isOn: Bool, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 5)
                .frame(width: 30, height: 32, alignment: .top)
                .foregroundStyle(isOn ? (filled ? Color.black.opacity(0.82) : Otter.accent) : Otter.textSecondary)
                .background {
                    if isOn {
                        Capsule().fill(filled ? Otter.accent : Otter.accent.opacity(0.18))
                    }
                }
                .overlay(alignment: .bottom) {
                    if let letter {
                        // Combinaison complète : « B » seul laissait croire
                        // qu'il suffisait d'appuyer sur la lettre.
                        Text("⌃⌥\(letter)")
                            .font(.system(size: 6, weight: .bold, design: .rounded))
                            .foregroundStyle(isOn && filled ? Color.black.opacity(0.55) : Otter.textTertiary)
                            .strikethrough(shortcutFailed(letter))
                            .padding(.bottom, 3)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(OtterPressStyle(scale: 0.9))
        .help(letter.map { shortcutFailed($0) ? "\(title) — ⌃⌥\($0) est déjà pris par une autre app" : "\(title) — ⌃⌥\($0)" } ?? title)
    }

    private func swatch(_ hex: String) -> some View {
        let selected = style.prefs.colorHex.uppercased() == hex.uppercased()
        return Button {
            live.selectColor(hex)
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 15, height: 15)
                .overlay(Circle().stroke(Color.white.opacity(selected ? 1 : 0.15), lineWidth: selected ? 2 : 0.75))
                .padding(1)
        }
        .buttonStyle(OtterPressStyle(scale: 0.88))
        .help(hex)
    }
}
