import SwiftUI

/// Page « Apparence ».
///
/// Deux niveaux pour ne perdre personne : par défaut, un style en un clic
/// (OtterIsland, Système, Personnalisé) puis, en Personnalisé, l'essentiel —
/// couleur d'accent et fond. L'interrupteur « Réglages avancés » déplie le
/// reste : opacité, contraste, arrondi, ombre, reflets, tuiles. Un aperçu de
/// l'île en tête suit chaque réglage en direct.
struct AppearanceSettingsView: View {
    @ObservedObject private var appearance = OtterAppearance.shared
    /// Roues des couleurs dépliées.
    @State private var showAccentWheel = false
    @State private var showTintWheel = false

    var body: some View {
        Form {
            Section {
                IslandPreview()
                    .frame(height: 128)
                    .listRowInsets(EdgeInsets())
            } footer: {
                caption("Aperçu de l'île ouverte sur un fond d'écran coloré : il suit chaque réglage en direct.")
            }

            Section {
                Picker("Style", selection: $appearance.style) {
                    ForEach(OtterAppearance.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Style")
            } footer: {
                caption(appearance.style.detail)
            }

            if appearance.style == .custom {
                accentSection
                backgroundSection

                Section {
                    Toggle(isOn: $appearance.showAdvanced) {
                        Text("Réglages avancés")
                        Text("Opacité, contraste, arrondi, ombre, reflets du verre, intensité des tuiles. Tout se remet d'origine d'un clic.")
                    }
                }

                if appearance.showAdvanced {
                    glassSection
                    shapeSection
                    Section {
                        Button("Remettre les réglages avancés d'origine") { appearance.resetAdvanced() }
                    }
                }
            }

            Section {
                Button("Revenir à l'apparence d'origine") { appearance.reset() }
            } footer: {
                caption("Style OtterIsland, accent aqua, verre sombre : l'apparence de la première installation.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Sections

    private var accentSection: some View {
        Section {
            swatches(OtterAppearance.accentPresets, selection: $appearance.accentHex)
            DisclosureGroup("Roue des couleurs", isExpanded: $showAccentWheel) {
                ColorWheelPicker(hex: appearance.accentHex == OtterAppearance.systemAccentToken
                                    ? NSColor(appearance.accent).hexString : appearance.accentHex) {
                    appearance.accentHex = $0
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Couleur d'accentuation")
        } footer: {
            caption("Utilisée pour l'onglet actif, les jauges, les liens et les boutons principaux. « Couleur du système » reprend celle de Réglages Système › Apparence et la suit si tu la changes. Pour une harmonie sobre, essaie Graphite ou Blanc.")
        }
    }

    private var backgroundSection: some View {
        Section {
            Picker("Matériau", selection: $appearance.material) {
                ForEach(OtterAppearance.Material.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            caption(materialDetail)
            swatches(OtterAppearance.tintPresets, selection: $appearance.tintHex)
            DisclosureGroup("Roue des couleurs", isExpanded: $showTintWheel) {
                ColorWheelPicker(hex: appearance.tintHex) { appearance.tintHex = $0 }
                    .padding(.vertical, 6)
            }
        } header: {
            Text("Fond de l'île")
        } footer: {
            caption("La teinte colore le verre de l'île. Le noir garde le texte blanc parfaitement lisible ; une teinte très claire le rendrait difficile à lire.")
        }
    }

    private var glassSection: some View {
        Section {
            slider("Opacité de la teinte", value: $appearance.glassOpacity, in: 0.2...0.95,
                   format: percent, default: OtterAppearance.Default.glassOpacity,
                   detail: "Plus haut : verre plus sombre et plus calme. Plus bas : le fond d'écran transparaît davantage. Sans effet en Opaque.")
                .disabled(appearance.material == .solid)
            slider("Contraste du texte", value: $appearance.readability, in: 0...2,
                   format: percent, default: OtterAppearance.Default.readability,
                   detail: "Voile sombre posé sous le texte. Monte-le si le texte se perd sur un fond d'écran clair ; baisse-le pour un verre plus pur.")
            slider("Intensité des tuiles", value: $appearance.tileIntensity, in: 0...2.5,
                   format: percent, default: OtterAppearance.Default.tileIntensity,
                   detail: "Fond des modules posés sur le verre (indicateurs, calendrier, lecteur). À 0, les modules disparaissent et le contenu flotte sur le verre.")
        } header: {
            Text("Verre")
        }
    }

    private var shapeSection: some View {
        Section {
            slider("Arrondi des coins", value: $appearance.cornerRadius, in: 12...40,
                   format: { "\(Int($0.rounded())) pt" }, default: OtterAppearance.Default.cornerRadius,
                   detail: "Coins du bas de l'île ouverte. Petit : plus net, façon fenêtre. Grand : plus doux, façon goutte d'eau.")
            slider("Ombre portée", value: $appearance.shadow, in: 0...0.8,
                   format: percent, default: OtterAppearance.Default.shadow,
                   detail: "Décolle l'île du bureau. À 0, elle se pose à plat sur l'écran.")
            slider("Reflet sur le bord", value: $appearance.rim, in: 0...1.5,
                   format: percent, default: OtterAppearance.Default.rim,
                   detail: "Liseré lumineux sur la tranche du verre : c'est lui qui donne l'effet de verre épais. À 0, un bord net et mat.")
            Toggle(isOn: $appearance.accentGradient) {
                Text("Accent en dégradé")
                Text("Un léger dégradé fait briller l'onglet actif ; décoché, un aplat de couleur, plus sobre.")
            }
        } header: {
            Text("Forme et profondeur")
        }
    }

    private var materialDetail: String {
        switch appearance.material {
        case .liquid: return "Liquid Glass : le verre de macOS, le fond d'écran vit à travers. Son flou est fixé par macOS."
        case .frosted: return "Verre dépoli : flou marqué, plus calme, le fond d'écran ne se devine plus qu'en couleurs."
        case .solid: return "Opaque : la teinte seule, sans transparence ni reflet du bureau. Le plus sobre."
        }
    }

    // MARK: Pièces

    private var percent: (Double) -> String { { "\(Int(($0 * 100).rounded())) %" } }

    /// Réglette : titre et valeur, curseur, explication, retour à la valeur d'origine.
    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        format: @escaping (Double) -> String, default defaultValue: Double,
                        detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if abs(value.wrappedValue - defaultValue) > 0.001 {
                    Button {
                        value.wrappedValue = defaultValue
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Revenir à \(format(defaultValue))")
                }
            }
            Slider(value: value, in: range)
            caption(detail)
        }
    }

    /// Rangée de pastilles de couleur, la sélection cerclée, le nom au survol.
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

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Miniature de l'île ouverte sur un faux fond d'écran : verre, onglet actif,
/// module, texte. Observe l'apparence, donc suit les réglages en direct.
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
                NotchGlassBackground(
                    topWidth: 90, topHeight: 14,
                    bottomRadius: CGFloat(appearance.effectiveCornerRadius) * 0.75,
                    isExpanded: true
                )
                VStack(alignment: .leading, spacing: 7) {
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
                    // Un module, pour juger l'intensité des tuiles.
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Banlieusards").font(.system(size: 11, weight: .semibold))
                        Text("Kery James").font(.system(size: 9.5)).foregroundStyle(Otter.textSecondary)
                        Capsule().fill(Otter.chipFill).frame(height: 3)
                            .overlay(alignment: .leading) { Capsule().fill(Otter.accent).frame(width: 90, height: 3) }
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Otter.tileFill))
                }
                .foregroundStyle(Otter.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 20)
            }
            .frame(width: 270, height: 112)
            .shadow(color: .black.opacity(appearance.effectiveShadow), radius: 8, y: 4)
        }
        .clipped()
    }
}
