import AppKit
import SwiftUI

/// Sélecteur de couleur intégré au panneau du Live.
///
/// Il remplace le `ColorPicker` système, qui ouvrait le panneau de couleurs
/// partagé de macOS : un seul panneau pour deux réglages (trait et effet du
/// curseur), affiché SOUS la couche du Live pendant une présentation, et dont
/// la couleur revenait d'un aller-retour par l'hexadécimal à chaque mouvement
/// — d'où une roue qui « sautait » et des choix qui ne prenaient pas.
///
/// Ici la couleur en cours d'édition vit dans l'état local (teinte,
/// saturation, luminosité) ; elle est appliquée à chaque mouvement, et
/// l'arrivée de la valeur appliquée ne réinitialise pas le curseur.
struct LiveColorPicker: View {
    /// Couleur actuellement appliquée (hex « #RRGGBB »).
    let hex: String
    let onChange: (String) -> Void
    var onAddToPalette: ((String) -> Void)?

    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var hexText = ""
    @State private var hexError = false
    /// Dernière valeur émise : sert à reconnaître notre propre écho.
    @State private var lastEmitted = ""

    private var currentHex: String {
        NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: brightness, alpha: 1).hexString
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 10) {
                saturationBrightnessSquare
                    .frame(height: 140)
                hueBar
                    .frame(height: 14)
            }
            .frame(maxWidth: 260)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: currentHex))
                    .frame(width: 64, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                TextField("#RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 100)
                    .onSubmit(applyHexText)
                Button("Appliquer le code", action: applyHexText)
                    .controlSize(.small)
                if let onAddToPalette {
                    Button("Ajouter à la palette") { onAddToPalette(currentHex) }
                        .controlSize(.small)
                }
                if hexError {
                    Text("Format : #RRGGBB")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear { load(hex) }
        .onChange(of: hex) { _, newValue in
            // Notre propre écho : ne pas recaler le curseur (c'est ce qui
            // faisait sauter la roue système).
            guard newValue.uppercased() != lastEmitted.uppercased() else { return }
            load(newValue)
        }
    }

    // MARK: Carré saturation × luminosité

    private var saturationBrightnessSquare: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: NSColor(colorSpace: .sRGB, hue: hue, saturation: 1, brightness: 1, alpha: 1))
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color(hex: currentHex)))
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(x: saturation * geo.size.width, y: (1 - brightness) * geo.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        saturation = min(1, max(0, value.location.x / max(1, geo.size.width)))
                        brightness = 1 - min(1, max(0, value.location.y / max(1, geo.size.height)))
                        emit()
                    }
            )
        }
    }

    // MARK: Barre de teinte

    private var hueBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                        Color(nsColor: NSColor(colorSpace: .sRGB, hue: $0, saturation: 1, brightness: 1, alpha: 1))
                    },
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(Capsule())
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color(nsColor: NSColor(colorSpace: .sRGB, hue: hue, saturation: 1, brightness: 1, alpha: 1))))
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: hue * geo.size.width - 9)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(1, max(0, value.location.x / max(1, geo.size.width)))
                        emit()
                    }
            )
        }
    }

    // MARK: Logique

    private func emit() {
        let value = currentHex
        hexText = value
        hexError = false
        guard value != lastEmitted else { return }
        lastEmitted = value
        onChange(value)
    }

    private func applyHexText() {
        guard let normalized = NSColor.normalizedHex(hexText) else {
            hexError = true
            return
        }
        hexError = false
        load(normalized)
        lastEmitted = normalized
        onChange(normalized)
    }

    private func load(_ value: String) {
        guard let color = NSColor(hex: value)?.usingColorSpace(.sRGB) else { return }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Gris : la teinte n'a pas de sens, on garde celle en cours plutôt que
        // de sauter au rouge.
        if s > 0.001 { hue = Double(h) }
        saturation = Double(s)
        brightness = Double(b)
        hexText = NSColor.normalizedHex(value) ?? value
        lastEmitted = hexText
    }
}
