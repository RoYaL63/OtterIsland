import SwiftUI

/// Page « Apparence » : accent, teinte et opacité du verre, matériau,
/// contraste. Un aperçu de l'île en tête suit chaque réglage en direct.
struct AppearanceSettingsView: View {
    @ObservedObject private var appearance = OtterAppearance.shared

    var body: some View {
        Form {
            Section {
                IslandPreview()
                    .frame(height: 118)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("Style", selection: $appearance.style) {
                    ForEach(OtterAppearance.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                caption(appearance.style.detail)
            }

            if appearance.style == .custom {
                customSections
            }

            Section {
                Button("Revenir à l'apparence d'origine") { appearance.reset() }
            }
        }
        .formStyle(.grouped)
    }

    /// Réglages fins, seulement en style Personnalisé.
    @ViewBuilder
    private var customSections: some View {
            Section {
                swatches(OtterAppearance.accentPresets, selection: $appearance.accentHex)
                ColorPicker("Couleur personnalisée", selection: accentBinding, supportsOpacity: false)
            } header: {
                Text("Couleur d'accentuation")
            } footer: {
                caption("Onglet actif, liens, interrupteurs de l'île. « Couleur du système » suit Réglages Système › Apparence.")
            }

            Section {
                Picker("Matériau", selection: $appearance.material) {
                    ForEach(OtterAppearance.Material.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                swatches(OtterAppearance.tintPresets, selection: $appearance.tintHex)
                ColorPicker("Teinte personnalisée", selection: tintBinding, supportsOpacity: false)
                slider("Opacité de la teinte", value: $appearance.glassOpacity, in: 0.2...0.95)
                    .disabled(appearance.material == .solid)
                slider("Contraste du texte", value: $appearance.readability, in: 0...2)
            } header: {
                Text("Fond de l'île")
            } footer: {
                caption("Liquid Glass laisse vivre le fond d'écran ; Verre dépoli le floute davantage ; Opaque n'en montre rien, pour l'harmonie la plus sobre. Plus d'opacité = un verre plus sombre et plus calme. Le flou du Liquid Glass est fixé par macOS : pour plus de flou, choisis Verre dépoli.")
            }
    }

    // MARK: Pièces

    private var accentBinding: Binding<Color> {
        Binding(
            get: { appearance.accent },
            set: { appearance.accentHex = NSColor($0).hexString }
        )
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { appearance.tint },
            set: { appearance.tintHex = NSColor($0).hexString }
        )
    }

    /// Rangée de pastilles de couleur, la sélection cerclée.
    private func swatches(_ presets: [(name: String, hex: String)], selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.hex) { preset in
                let selected = selection.wrappedValue.caseInsensitiveCompare(preset.hex) == .orderedSame
                Button {
                    selection.wrappedValue = preset.hex
                } label: {
                    Circle()
                        .fill(color(for: preset.hex))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.18)))
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for hex: String) -> Color {
        hex == OtterAppearance.systemAccentToken
            ? Color(nsColor: .controlAccentColor)
            : Color(hex: hex, fallback: .gray)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) : \(Int((value.wrappedValue * 100).rounded())) %")
            Slider(value: value, in: range)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Miniature de l'île ouverte sur un faux fond d'écran : verre, onglet actif,
/// texte. Observe l'apparence, donc suit les curseurs en direct.
private struct IslandPreview: View {
    @ObservedObject private var appearance = OtterAppearance.shared

    var body: some View {
        ZStack(alignment: .top) {
            // Faux fond d'écran contrasté : on juge la transparence sur du vivant.
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.65, blue: 0.35), Color(red: 0.36, green: 0.42, blue: 0.75), Color(red: 0.14, green: 0.38, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ZStack(alignment: .topLeading) {
                NotchGlassBackground(topWidth: 90, topHeight: 14, bottomRadius: 20, isExpanded: true)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                        Text("Live").font(.system(size: 9.5, weight: .semibold))
                        Spacer(minLength: 0)
                        ForEach(["square.grid.2x2.fill", "doc.on.clipboard", "music.note", "calendar"], id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 9.5, weight: .semibold))
                                .frame(width: 22, height: 18)
                                .foregroundStyle(icon == "music.note" ? Otter.onAccent : Otter.textSecondary)
                                .background {
                                    if icon == "music.note" { Capsule().fill(Otter.accentGradient) }
                                }
                        }
                    }
                    Text("Banlieusards").font(.system(size: 11, weight: .semibold))
                    Capsule().fill(Otter.chipFill).frame(height: 3)
                        .overlay(alignment: .leading) { Capsule().fill(Otter.accent).frame(width: 90, height: 3) }
                }
                .foregroundStyle(Otter.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 20)
            }
            .frame(width: 260, height: 96)
        }
        .clipped()
    }
}
