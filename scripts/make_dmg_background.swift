// Fond de la fenêtre d'installation (.dmg).
//
//   swift scripts/make_dmg_background.swift [sortie.png]
//
// 660×420, plus une version @2x pour les écrans Retina. Palette reprise de
// l'icône. Fond CLAIR volontairement : dans une fenêtre du Finder, le libellé
// sous les icônes est écrit en sombre, il devient illisible sur fond foncé.

import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"

// Repères partagés avec make_dmg.sh : si tu bouges les icônes là-bas, bouge la
// flèche ici. Coordonnées en points, origine en haut à gauche.
let size = CGSize(width: 660, height: 420)
let appSpot = CGPoint(x: 165, y: 205)
let folderSpot = CGPoint(x: 495, y: 205)

let deepTeal = NSColor(red: 0.039, green: 0.278, blue: 0.271, alpha: 1)   // #0A4745
let aqua = NSColor(red: 0.169, green: 0.702, blue: 0.624, alpha: 1)       // aqua assombri, lisible sur fond clair
let topTint = NSColor(red: 0.918, green: 0.984, blue: 0.969, alpha: 1)
let bottomTint = NSColor(red: 0.839, green: 0.953, blue: 0.933, alpha: 1)

/// Dessine le fond à l'échelle demandée (1 = 660×420, 2 = Retina).
func render(scale: CGFloat) -> Data? {
    let pixels = CGSize(width: size.width * scale, height: size.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)

    // Repère en haut à gauche, comme les coordonnées d'icônes du Finder.
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)

    NSGradient(starting: topTint, ending: bottomTint)?
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // Flèche entre les deux emplacements d'icônes, arrêtée bien avant chacun
    // pour ne pas passer sous les vignettes de 128 pt.
    let start = CGPoint(x: appSpot.x + 96, y: appSpot.y)
    let end = CGPoint(x: folderSpot.x - 96, y: folderSpot.y)
    ctx.setStrokeColor(aqua.cgColor)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.move(to: start)
    ctx.addLine(to: CGPoint(x: end.x - 14, y: end.y))
    ctx.strokePath()

    ctx.setFillColor(aqua.cgColor)
    ctx.move(to: end)
    ctx.addLine(to: CGPoint(x: end.x - 20, y: end.y - 13))
    ctx.addLine(to: CGPoint(x: end.x - 20, y: end.y + 13))
    ctx.closePath()
    ctx.fillPath()

    func draw(_ text: String, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, centerY: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let width = string.size().width
        // Le contexte est retourné : on redresse le texte le temps de l'écrire.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: centerY)
        ctx.scaleBy(x: 1, y: -1)
        string.draw(at: NSPoint(x: (size.width - width) / 2, y: -string.size().height / 2))
        ctx.restoreGState()
    }

    draw("Glisse OtterIsland dans Applications", size: 21, weight: .semibold, color: deepTeal, centerY: 78)
    draw("L'app doit être dans Applications pour que macOS lui accorde",
         size: 12, weight: .regular, color: deepTeal.withAlphaComponent(0.65), centerY: 112)
    draw("l'Accessibilité et le lancement au démarrage.",
         size: 12, weight: .regular, color: deepTeal.withAlphaComponent(0.65), centerY: 130)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (scale, suffix) in [(CGFloat(1), ""), (CGFloat(2), "@2x")] {
    let path = output.replacingOccurrences(of: ".png", with: "\(suffix).png")
    guard let data = render(scale: scale) else {
        FileHandle.standardError.write(Data("error: rendu \(scale)x impossible\n".utf8))
        exit(1)
    }
    try? data.write(to: URL(fileURLWithPath: path))
    print("→ \(path)")
}
