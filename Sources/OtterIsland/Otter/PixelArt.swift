import SpriteKit

/// Génère une texture pixel-art à partir d'une grille d'indices de palette.
/// Zéro asset binaire dans le dépôt : la loutre est dessinée en code, et reste
/// remplaçable plus tard par une vraie feuille de sprites.
enum PixelArt {
    /// Palette par index. 0 = transparent. Valeurs calées sur le rendu PNG de
    /// validation (scripts/render_otter.py) — garder les deux synchronisés.
    static let otterPalette: [SKColor] = [
        .clear,                                                // 0 transparent
        SKColor(red: 0.47, green: 0.33, blue: 0.22, alpha: 1), // 1 marron corps
        SKColor(red: 0.87, green: 0.74, blue: 0.57, alpha: 1), // 2 crème ventre/museau
        SKColor(red: 0.13, green: 0.10, blue: 0.09, alpha: 1), // 3 yeux / nez
        SKColor(red: 0.95, green: 0.61, blue: 0.60, alpha: 1), // 4 rose joues / oreilles
        SKColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1), // 5 reflet
        SKColor(red: 0.29, green: 0.19, blue: 0.13, alpha: 1), // 6 contour sombre
        SKColor(red: 0.43, green: 0.69, blue: 0.82, alpha: 1), // 7 bleu d'eau (nage)
    ]

    /// Construit une SKTexture nette (nearest) depuis une grille [ligne][colonne].
    /// La grille est lue du haut vers le bas ; on l'inverse pour l'orientation SpriteKit.
    static func texture(from grid: [[Int]], palette: [SKColor]) -> SKTexture {
        let height = grid.count
        let width = grid.first?.count ?? 0
        guard width > 0, height > 0 else { return SKTexture() }

        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for row in 0..<height {
            for col in 0..<width {
                let index = grid[height - 1 - row][col] // inversion verticale
                let color = palette.indices.contains(index) ? palette[index] : .clear
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
                let offset = (row * width + col) * bytesPerPixel
                pixels[offset + 0] = UInt8(r * 255)
                pixels[offset + 1] = UInt8(g * 255)
                pixels[offset + 2] = UInt8(b * 255)
                pixels[offset + 3] = UInt8(a * 255)
            }
        }

        let data = Data(pixels)
        let texture = SKTexture(
            data: data,
            size: CGSize(width: width, height: height)
        )
        texture.filteringMode = .nearest // garde le rendu pixel net
        return texture
    }
}
