import AppKit
import ApplicationServices
import SwiftUI

/// Fenêtre « Personnaliser le Live ». L'island garde l'essentiel (outils,
/// 5 couleurs, durée) ; tout le reste — sélecteur de couleur, codes hexa,
/// effets de curseur, masquage — vit ici, à un clic du bouton ⚙︎ de la barre.
@MainActor
final class LiveCustomizeWindowController {
    private weak var live: LiveController?
    private var window: NSWindow?

    init(live: LiveController) {
        self.live = live
    }

    func show() {
        guard let live else { return }
        let win = window ?? makeWindow(live: live)
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(live: LiveController) -> NSWindow {
        let host = NSHostingView(rootView: LiveCustomizeView(live: live, style: live.style))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Personnaliser le Live"
        win.contentView = host
        win.isReleasedWhenClosed = false
        // Au-dessus de l'overlay du Live, pour rester utilisable pendant une
        // présentation.
        win.level = .statusBar
        win.center()
        return win
    }
}

struct LiveCustomizeView: View {
    @ObservedObject var live: LiveController
    @ObservedObject var style: LiveStyle

    /// Ce que modifient la palette et le sélecteur.
    enum ColorTarget: String, CaseIterable, Identifiable {
        case stroke = "Trait"
        case effect = "Effet du curseur"
        var id: String { rawValue }
    }

    @State private var target: ColorTarget = .stroke

    var body: some View {
        Form {
            colorSection
            strokeSection
            cursorSection
            spotlightSection
            keysSection
            privacySection
            shortcutsSection
            Section {
                HStack {
                    Button("Réinitialiser les réglages du Live") { style.resetToDefaults() }
                    Spacer()
                    Button(live.isActive ? "Arrêter le Live" : "Démarrer le Live") { live.toggle() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
    }

    // MARK: Trait

    private var colorSection: some View {
        Section("Couleurs") {
            Picker("Modifier", selection: $target) {
                ForEach(ColorTarget.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text(target == .stroke
                     ? "Palette — les 5 premières couleurs apparaissent dans l'island. Clic droit pour copier le code ou retirer."
                     : "Clique une couleur de la palette ou un préréglage pour l'effet du curseur.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                    ForEach(style.prefs.palette, id: \.self) { hex in
                        swatch(hex)
                    }
                }
                if target == .effect {
                    HStack(spacing: 6) {
                        ForEach(Self.effectPresets) { preset in
                            Button(preset.name) { style.prefs.cursorEffectHex = preset.hex }
                                .controlSize(.small)
                        }
                    }
                }
            }

            LiveColorPicker(
                hex: targetHex,
                onChange: { setTargetHex($0) },
                onAddToPalette: { style.addToPalette($0, select: target == .stroke) }
            )
            .padding(.vertical, 4)
            Text("Les changements s'appliquent tout de suite, Live allumé ou non.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var targetHex: String {
        target == .stroke ? style.prefs.colorHex : style.prefs.cursorEffectHex
    }

    private func setTargetHex(_ hex: String) {
        if target == .stroke { style.prefs.colorHex = hex } else { style.prefs.cursorEffectHex = hex }
    }

    private var strokeSection: some View {
        Section("Trait") {
            LabeledContent("Épaisseur") {
                HStack {
                    Slider(value: binding(\.strokeWidth), in: 2...12, step: 1)
                    Text("\(Int(style.prefs.strokeWidth)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("S'efface après") {
                Picker("", selection: binding(\.fadeSeconds)) {
                    Text("3 s").tag(3.0)
                    Text("5 s").tag(5.0)
                    Text("8 s").tag(8.0)
                    Text("10 s").tag(10.0)
                    Text("20 s").tag(20.0)
                    Text("Jamais").tag(0.0)
                }
                .labelsHidden()
                .frame(width: 120)
            }
            Toggle("Lueur autour des traits", isOn: binding(\.glow))
            Toggle("Redresser les formes (flèche, cercle, rectangle tracés à main levée)", isOn: binding(\.straightenShapes))
            LabeledContent("Dessiner en maintenant") {
                Picker("", selection: binding(\.drawModifier)) {
                    ForEach(LiveDrawModifier.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let selected = targetHex.uppercased() == hex.uppercased()
        return Button {
            setTargetHex(hex)
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(selected ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .help(hex)
        .contextMenu {
            Button("Copier \(hex)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
            }
            Button("Retirer de la palette") {
                style.prefs.palette.removeAll { $0 == hex }
            }
            .disabled(style.prefs.palette.count <= 1)
        }
    }

    // MARK: Curseur

    private var cursorSection: some View {
        Section("Curseur") {
            Picker("Effet", selection: binding(\.cursorEffect)) {
                ForEach(LiveCursorEffect.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(style.prefs.cursorEffect.detail)
                .font(.caption).foregroundStyle(.secondary)
            if style.prefs.cursorEffect != .none {
                HStack {
                    Circle().fill(Color(hex: style.prefs.cursorEffectHex)).frame(width: 14, height: 14)
                    Text("Couleur : \(style.prefs.cursorEffectHex)").font(.callout.monospaced())
                    Spacer()
                    Button("Changer la couleur") { target = .effect }
                        .controlSize(.small)
                }
                LabeledContent("Taille") {
                    Slider(value: binding(\.cursorEffectSize), in: 0.6...2)
                }
            }
            Toggle("Animation au clic (anneau à gauche, double anneau au double-clic, losange à droite)", isOn: binding(\.clickRipples))
        }
    }

    // MARK: Projecteur

    private var spotlightSection: some View {
        Section("Projecteur") {
            LabeledContent("Rayon") {
                HStack {
                    Slider(value: binding(\.spotlightRadius), in: 60...300)
                    Text("\(Int(style.prefs.spotlightRadius)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
            LabeledContent("Obscurité") {
                Slider(value: binding(\.spotlightDarkness), in: 0.3...0.85)
            }
        }
    }

    // MARK: Touches

    private var keysSection: some View {
        Section("Touches affichées") {
            Toggle("Afficher les raccourcis tapés", isOn: binding(\.showKeys))
            Text("Seulement les combinaisons avec ⌘ ou ⌃, et Échap — jamais le texte tapé (⌥ seul sert à taper des caractères de mots de passe).")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Position", selection: binding(\.keysPosition)) {
                ForEach(LiveKeysPosition.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent("Taille") {
                Slider(value: binding(\.keysScale), in: 0.7...1.6)
            }
            if !AXIsProcessTrusted() {
                HStack {
                    Text("Les touches et le masquage des clés demandent l'autorisation Accessibilité.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Autoriser") { Paster.ensureAccessibility() }.controlSize(.small)
                }
            }
        }
    }

    // MARK: Confidentialité

    private var privacySection: some View {
        Section("Confidentialité") {
            Toggle("Masquer les clés API et mots de passe visibles", isOn: binding(\.maskSecrets))
            Text("OpenAI, Anthropic, Stripe, GitHub, AWS, Google, Slack, Airtable, Notion, jetons JWT, webhooks Make, et toute valeur après « password = », « api_key: »… Lu dans le champ actif via l'Accessibilité, deux fois par seconde.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Masquer des applications entières", isOn: binding(\.maskApps))
            if style.prefs.maskApps {
                ForEach(style.prefs.maskedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(appName(bundleID))
                        Text(bundleID).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            style.prefs.maskedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Ajouter une application ouverte") {
                    ForEach(runningApps) { app in
                        Button(app.name) {
                            if !style.prefs.maskedBundleIDs.contains(app.bundleID) {
                                style.prefs.maskedBundleIDs.append(app.bundleID)
                            }
                        }
                    }
                }
            }
            Toggle("Concentration pendant le Live", isOn: binding(\.focusDuringLive))
            Text("Coupe les notifications à l'écran. Utilise les raccourcis Concentration réglés dans Réglages › Concentration (les mêmes que le Pomodoro).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Rappel : dessins et masques ne se voient que si tu partages l'écran ENTIER, pas une seule fenêtre.")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private struct RunningApp: Identifiable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    private struct EffectPreset: Identifiable {
        let name: String
        let hex: String
        var id: String { name }
    }

    private static let effectPresets = [
        EffectPreset(name: "Feu", hex: "#FFB340"),
        EffectPreset(name: "Glace", hex: "#7FDBFF"),
        EffectPreset(name: "Menthe", hex: "#5EE9D3"),
        EffectPreset(name: "Rose", hex: "#FF2D95"),
        EffectPreset(name: "Or", hex: "#FFD60A"),
    ]

    private var runningApps: [RunningApp] {
        var result: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier,
                  !style.prefs.maskedBundleIDs.contains(bundleID),
                  !result.contains(where: { $0.bundleID == bundleID })
            else { continue }
            result.append(RunningApp(name: app.localizedName ?? bundleID, bundleID: bundleID))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    // MARK: Raccourcis

    private var shortcutsSection: some View {
        Section("Raccourcis (⌃⌥ + touche)") {
            if live.toggleHotKeyFailed {
                Text("⌃⌥L est déjà pris par une autre app : utilise le bouton de l'island pour lancer le Live.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(LiveController.shortcuts) { shortcut in
                HStack {
                    Text(shortcut.title)
                    if live.failedShortcuts.contains(shortcut.id) {
                        Text("déjà pris par une autre app")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(shortcut.id == "zoom" ? "⌥⌘8" : "⌃⌥\(shortcut.letter)")
                        .font(.body.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
            }
            Text("En mode stylo : Échap efface tout et rend la souris, un clic sur un dessin l'efface. Le Live ne capture aucun raccourci des apps : ⌘Z, ⌘V ou le raccourci du presse-papier continuent de marcher.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Liaisons

    private func binding<T>(_ keyPath: WritableKeyPath<LivePreferences, T>) -> Binding<T> {
        Binding(
            get: { style.prefs[keyPath: keyPath] },
            set: { style.prefs[keyPath: keyPath] = $0 }
        )
    }

}
