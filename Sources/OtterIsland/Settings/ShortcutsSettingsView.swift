import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Page « Raccourcis et barre » : les raccourcis de l'île, et la flèche qui
/// plie la barre des menus.
struct ShortcutsSettingsView: View {
    @EnvironmentObject var settings: OtterSettings
    @ObservedObject private var store = QuickShortcutStore.shared
    @State private var linkTitle = ""
    @State private var linkAddress = ""
    @State private var linkError = false
    @State private var macShortcuts: [String] = []

    var body: some View {
        Form {
            Section {
                if store.items.isEmpty {
                    caption("Aucun raccourci pour l'instant. Ajoute-en avec les boutons ci-dessous : ils apparaissent dans l'onglet Raccourcis de l'île.")
                }
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                }
            } header: {
                Text("Raccourcis de l'île")
            } footer: {
                caption("Un clic dans l'onglet Raccourcis (éclair) ouvre l'app, le dossier ou le lien, ou exécute le raccourci macOS. Les flèches changent l'ordre.")
            }

            Section("Ajouter") {
                HStack {
                    Button("App…") { pick(apps: true) }
                    Button("Dossier ou fichier…") { pick(apps: false) }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lien")
                    // Champs sans libellé : dans un formulaire groupé, un
                    // libellé de TextField devient une colonne à gauche et
                    // écrase le champ.
                    HStack {
                        TextField("", text: $linkTitle, prompt: Text("Nom (facultatif)"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                        TextField("", text: $linkAddress, prompt: Text("exemple.fr, mailto:…, slack://…"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addLink)
                        Button("Ajouter", action: addLink)
                    }
                    if linkError {
                        Text("Adresse illisible.").font(.caption).foregroundStyle(.red)
                    }
                }
                HStack {
                    Menu("Raccourci macOS…") {
                        if macShortcuts.isEmpty {
                            Text("Aucun raccourci dans l'app Raccourcis")
                        }
                        ForEach(macShortcuts, id: \.self) { name in
                            Button(name) {
                                store.add(QuickShortcut(kind: .shortcut, title: name, target: name))
                            }
                        }
                    }
                    .fixedSize()
                    Spacer()
                }
            }

            menuBarSection
        }
        .formStyle(.grouped)
        .onAppear { macShortcuts = FocusMode.availableShortcuts() }
    }

    // MARK: Barre des menus

    private var menuBarSection: some View {
        Section {
            Toggle(isOn: $settings.menuBarManagerEnabled) {
                Text("Flèche pour plier la barre des menus")
                Text("Quand une app a un long menu, macOS cache sans prévenir les icônes de droite qui ne tiennent plus. Avec la flèche, c'est toi qui choisis celles qui peuvent disparaître.")
            }
            if settings.menuBarManagerEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mode d'emploi").font(.callout.weight(.semibold))
                    step(1, "Deux éléments sont apparus dans la barre des menus, à gauche de la loutre : une flèche › et un trait │.")
                    step(2, "Maintiens ⌘ et glisse, à gauche du trait │, les icônes que tu veux pouvoir cacher.")
                    step(3, "Clique sur la flèche : tout ce qui est à gauche du trait disparaît. Reclique (‹) pour le faire revenir, ou passe par l'onglet Raccourcis de l'île.")
                    caption("Le trait doit rester à gauche de la flèche : sinon OtterIsland refuse de plier, pour ne jamais cacher la flèche elle-même. Clic droit sur la flèche : ce mode d'emploi.")
                }
                Toggle("Replier au lancement d'OtterIsland", isOn: $settings.menuBarCollapseAtLaunch)
                Picker("Replier tout seul", selection: $settings.menuBarAutoCollapseDelay) {
                    Text("Jamais").tag(0.0)
                    Text("Après 10 s").tag(10.0)
                    Text("Après 15 s").tag(15.0)
                    Text("Après 30 s").tag(30.0)
                    Text("Après 1 min").tag(60.0)
                }
            }
        } header: {
            Text("Barre des menus")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    // MARK: Liste

    private func row(_ item: QuickShortcut, index: Int) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon = item.fileIcon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: item.symbol).foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                Text(item.isMissing ? "\(item.kindLabel) · introuvable" : "\(item.kindLabel) · \(displayTarget(item))")
                    .font(.caption)
                    .foregroundStyle(item.isMissing ? .orange : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button { store.move(item, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { store.move(item, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == store.items.count - 1)
            Button(role: .destructive) { store.remove(item) } label: { Image(systemName: "trash") }
                .help("Retirer ce raccourci")
        }
        .buttonStyle(.borderless)
    }

    private func displayTarget(_ item: QuickShortcut) -> String {
        item.target.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: Ajout

    private func pick(apps: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        if apps {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.canChooseDirectories = false
            panel.prompt = "Ajouter"
        } else {
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.prompt = "Ajouter"
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            store.add(apps || url.pathExtension == "app" ? .app(at: url) : .file(at: url))
        }
    }

    private func addLink() {
        guard let item = QuickShortcut.link(title: linkTitle, address: linkAddress) else {
            linkError = true
            return
        }
        store.add(item)
        linkTitle = ""
        linkAddress = ""
        linkError = false
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
