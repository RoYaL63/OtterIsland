import Foundation

/// Expression du visage de la loutre.
enum OtterFace {
    case neutral, blink, happy, curious, sleepy, worried
}

/// Frames pixel-art (16x16). Un corps de base, sur lequel on tamponne les yeux
/// selon l'expression. Les yeux sont rangées 6-7, colonnes 5 (gauche) et 10 (droite) ;
/// le nez rose/foncé est déjà dans le corps. Retouche-les librement sur le Mac.
enum OtterSprites {
    /// Corps de base, sans yeux. Palette : 0 transparent, 1 marron, 2 ventre clair,
    /// 3 foncé, 4 rose, 5 reflet.
    private static let base: [[Int]] = [
        [0,0,0,1,1,0,0,0,0,0,0,1,1,0,0,0],
        [0,0,1,1,1,1,0,0,0,0,1,1,1,1,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,2,2,2,2,2,2,2,2,1,1,1,0],
        [0,1,1,2,2,2,2,2,2,2,2,2,2,1,1,0],
        [0,1,1,2,2,2,2,2,2,2,2,2,2,1,1,0],
        [0,1,1,2,2,2,2,2,2,2,2,2,2,1,1,0],
        [0,1,1,2,2,2,2,4,4,2,2,2,2,1,1,0],
        [0,1,1,2,2,2,2,3,3,2,2,2,2,1,1,0],
        [0,0,1,1,2,2,2,2,2,2,2,2,1,1,0,0],
        [0,0,1,1,1,2,2,2,2,2,2,1,1,1,0,0],
        [0,0,0,1,1,1,2,2,2,2,1,1,1,0,0,0],
        [0,0,0,1,1,1,1,2,2,1,1,1,1,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
    ]

    /// Corps avec l'expression demandée tamponnée.
    static func grid(for face: OtterFace) -> [[Int]] {
        var g = base
        func set(_ row: Int, _ col: Int, _ value: Int) { g[row][col] = value }

        switch face {
        case .neutral:
            for r in 6...7 { set(r, 5, 3); set(r, 10, 3) }

        case .blink:
            // yeux fermés : simple ligne foncée
            set(7, 5, 3); set(7, 10, 3)

        case .happy:
            // yeux souriants ^ ^
            set(6, 5, 3); set(6, 10, 3)
            set(7, 4, 3); set(7, 6, 3); set(7, 9, 3); set(7, 11, 3)

        case .curious:
            // grands yeux écarquillés avec un reflet
            for r in 6...7 { set(r, 5, 3); set(r, 6, 3); set(r, 9, 3); set(r, 10, 3) }
            set(6, 5, 5); set(6, 9, 5)

        case .sleepy:
            // paupières tombantes
            set(7, 4, 3); set(7, 5, 3); set(7, 10, 3); set(7, 11, 3)

        case .worried:
            // petits yeux timides, remontés
            set(6, 5, 3); set(6, 10, 3)
        }
        return g
    }

    /// Pose de nage dédiée : la loutre flotte sur le dos, pattes en l'air,
    /// tête à gauche (œil col 2), queue à droite. Utilisée quand la musique joue.
    static let swim: [[Int]] = [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0],
        [0,0,0,0,0,1,1,0,0,1,1,0,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,2,2,2,2,2,2,1,1,1,1,0],
        [0,1,3,2,2,2,2,2,2,2,2,1,1,1,1,1],
        [0,1,2,2,2,2,2,2,2,2,2,1,1,1,1,1],
        [0,1,1,2,2,2,2,2,2,2,2,1,1,1,1,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,0,0,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ]
}
