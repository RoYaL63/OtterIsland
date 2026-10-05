import AppKit
import SwiftUI

/// Roue des couleurs : teinte autour du cercle, saturation du centre (blanc)
/// vers le bord, luminosité au curseur, code hexadécimal à côté.
///
/// Même principe que `LiveColorPicker` : la couleur en cours d'édition vit
/// dans l'état local (teinte, saturation, luminosité) et l'écho de la valeur
/// appliquée ne recale pas le curseur. Sans ça, l'aller-retour par
/// l'hexadécimal fait « sauter » la roue à chaque mouvement.
struct ColorWheelPicker: View {
    /// Couleur appliquée (« #RRGGBB »).
    let hex: String
    let onChange: (String) -> Void

    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 1
    @State private var hexText = ""
    @State private var hexError = false
    @State private var lastEmitted = ""

    private var currentHex: String {
        NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: brightness, alpha: 1).hexString
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            wheel
                .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: currentHex))
                        .frame(width: 44, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.15)))
                    TextField("#RRGGBB", text: $hexText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 96)
                        .onSubmit(applyHexText)
                }
                if hexError {
                    Text("Format attendu : #RRGGBB").font(.caption).foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Luminosité : \(Int((brightness * 100).rounded())) %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // N'émet que sur un geste : un `onChange(of: brightness)`
                    // réagirait aussi au chargement et réécrirait la couleur
                    // enregistrée à la simple ouverture de la page.
                    Slider(value: Binding(get: { brightness }, set: { brightness = $0; emit() }), in: 0...1)
                }
                .frame(width: 150)
                Text("Clique ou glisse dans la roue : la teinte tourne, la couleur s'intensifie vers le bord.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 170, alignment: .leading)
            }
        }
        .onAppear { load(hex) }
        .onChange(of: hex) { _, newValue in
            guard newValue.caseInsensitiveCompare(lastEmitted) != .orderedSame else { return }
            load(newValue)
        }
    }

    // MARK: Roue

    private var wheel: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            ZStack {
                // Teinte autour du cercle. L'AngularGradient part de l'est et
                // tourne dans le sens horaire à l'écran : on suit la même
                // convention dans `pick` pour que la pastille tombe juste.
                Circle()
                    .fill(AngularGradient(
                        gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                            Color(hue: $0, saturation: 1, brightness: 1)
                        }),
                        center: .center
                    ))
                // Saturation : blanc au centre, couleur pure au bord.
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                // Luminosité : la roue s'assombrit avec le curseur.
                Circle()
                    .fill(Color.black.opacity(1 - brightness))
                Circle().stroke(Color.primary.opacity(0.15))

                // Pastille de la couleur choisie.
                let angle = hue * 2 * .pi
                let distance = saturation * radius
                Circle()
                    .fill(Color(hex: currentHex))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(x: radius + cos(angle) * distance, y: radius + sin(angle) * distance)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { pick($0.location, radius: radius) }
            )
        }
    }

    private func pick(_ point: CGPoint, radius: CGFloat) {
        let dx = point.x - radius
        let dy = point.y - radius
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        hue = Double(angle / (2 * .pi))
        saturation = Double(min(1, hypot(dx, dy) / radius))
        // Choisir une teinte sur une roue toute noire ne montrerait rien.
        if brightness < 0.15 { brightness = 1 }
        emit()
    }

    // MARK: Valeurs

    private func emit() {
        let value = currentHex
        lastEmitted = value
        hexText = value
        hexError = false
        onChange(value)
    }

    private func applyHexText() {
        guard let color = NSColor(hex: hexText) else {
            hexError = true
            return
        }
        hexError = false
        set(from: color)
        emit()
    }

    private func load(_ value: String) {
        hexText = value
        if let color = NSColor(hex: value) { set(from: color) }
    }

    private func set(from color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Gris : teinte indéfinie, on garde la teinte en cours plutôt que de
        // ramener la pastille au rouge.
        if s > 0.001 { hue = Double(h) }
        saturation = Double(s)
        brightness = Double(b)
    }
}
