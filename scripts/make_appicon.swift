#!/usr/bin/env swift
// Génère Resources/Assets.xcassets/AppIcon.appiconset depuis icone.png.
//
//   swift scripts/make_appicon.swift [source.png]
//
// Le PNG source est une illustration carrée sur fond blanc (sortie de
// générateur d'images). Trois choses à faire pour en tirer une vraie icône
// macOS :
//   1. rogner le fond blanc et l'ombre portée autour de la tuile,
//   2. découper la tuile en squircle (les coins doivent être TRANSPARENTS,
//      sinon macOS affiche un carré blanchâtre dans le Finder),
//   3. la recentrer sur la grille Apple (824 pt de contenu dans 1024) avec
//      l'ombre portée standard.
// Zéro dépendance : CoreGraphics suffit.

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = URL(fileURLWithPath: args.count > 1 ? args[1] : "icone.png", relativeTo: root)
let outputSet = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard let data = try? Data(contentsOf: source),
      let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(pngDataProviderSource: provider, decode: nil,
                          shouldInterpolate: true, intent: .defaultIntent)
else { fail("PNG illisible : \(source.path)") }

// MARK: - 1. Rogner le fond blanc

/// Boîte englobante de la tuile colorée. On teste la CHROMA (écart entre le
/// canal max et le canal min), pas la luminosité : l'ombre portée du rendu
/// source est un gris neutre (r≈g≈b) qui déborde largement de la tuile — un
/// seuil de luminosité l'attraperait et laisserait un halo blanc dans l'icône
/// finale. Le dégradé bleu/vert de la tuile, lui, est franchement saturé.
func contentBounds(of image: CGImage, threshold: Int = 60) -> CGRect {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &pixels, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return CGRect(x: 0, y: 0, width: w, height: h) }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2]), a = Int(pixels[i + 3])
            let chroma = max(r, g, b) - min(r, g, b)
            if a < 8 || chroma < threshold { continue }
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return CGRect(x: 0, y: 0, width: w, height: h) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

var box = contentBounds(of: image)
// La tuile est carrée : on garde le plus PETIT côté détecté, ancré en haut à
// gauche. L'ombre portée du rendu source est légèrement teintée de vert sous la
// tuile — elle passe le filtre de chroma et rallonge la boîte vers le bas de
// quelques dizaines de pixels. Les bords haut/gauche/droit, eux, sont nets.
let side = min(box.width, box.height)
box = CGRect(x: box.minX, y: box.minY, width: side, height: side)
    .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
// Mordre 1 % à l'intérieur : le bord de la tuile source est anti-aliasé contre
// le fond blanc, et ces quelques pixels clairs formaient un liseré blanc tout
// autour de l'icône une fois masquée.
box = box.insetBy(dx: side * 0.01, dy: side * 0.01)
guard let cropped = image.cropping(to: box) else { fail("recadrage impossible") }
print("source \(image.width)×\(image.height) → tuile \(Int(box.width))×\(Int(box.height)) à (\(Int(box.minX)), \(Int(box.minY)))")

// MARK: - 2 & 3. Squircle + grille Apple

/// Approximation du squircle macOS (Big Sur+) : rayon = 22.37 % du côté sur un
/// `CGPath` à coins arrondis continus. À la taille d'une icône la différence
/// avec la vraie superellipse est invisible.
func squircle(in rect: CGRect) -> CGPath {
    let radius = rect.width * 0.2237
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Dessine l'icône finale à `size` px : tuile masquée en squircle, occupant
/// 824/1024 du canevas, avec l'ombre portée douce des icônes système.
func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high

    // Grille Apple : 824 pt de contenu centré dans 1024, décalé de 12 pt vers
    // le haut pour laisser respirer l'ombre.
    let content = s * 824.0 / 1024.0
    let tile = CGRect(x: (s - content) / 2, y: (s - content) / 2 + s * 12.0 / 1024.0,
                      width: content, height: content)
    let path = squircle(in: tile)

    ctx.saveGState()
    // Ombre proportionnelle : invisible en 16 px, marquée en 1024 px.
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 10.0 / 1024.0),
                  blur: s * 20.0 / 1024.0,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.32))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(cropped, in: tile)
    ctx.restoreGState()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("encodage PNG") }
    try? png.write(to: url)
}

// MARK: - Écriture de l'asset catalog

try? FileManager.default.createDirectory(at: outputSet, withIntermediateDirectories: true)

/// (taille en points, échelle) → macOS attend les 10 variantes 16…512@2x.
let variants: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

var entries: [String] = []
var rendered: [Int: String] = [:]  // px → nom de fichier, pour ne pas rendre deux fois la même image

for variant in variants {
    let px = variant.pt * variant.scale
    let name: String
    if let existing = rendered[px] {
        name = existing
    } else {
        name = "icon_\(px).png"
        guard let img = renderIcon(size: px) else { fail("rendu \(px) px") }
        write(img, to: outputSet.appendingPathComponent(name))
        rendered[px] = name
    }
    entries.append("""
        {
          "size" : "\(variant.pt)x\(variant.pt)",
          "idiom" : "mac",
          "filename" : "\(name)",
          "scale" : "\(variant.scale)x"
        }
    """)
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}

"""
try? contents.write(to: outputSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("→ \(outputSet.path) (\(rendered.count) PNG)")
