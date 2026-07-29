import Foundation

/// Expression du visage de la loutre.
enum OtterFace {
    case neutral, blink, happy, curious, sleepy, worried
}

/// Frames pixel-art (20x20). Un corps de base sans yeux, sur lequel on tamponne
/// l'expression. Grille dessinée et validée visuellement via un rendu PNG
/// (script Python) avant transcription — ne pas retoucher à l'aveugle.
///
/// Palette : 0 transparent, 1 marron corps, 2 crème ventre/museau, 3 foncé
/// (yeux/nez), 4 rose (joues, intérieur d'oreilles), 5 reflet blanc,
/// 6 contour sombre, 7 bleu d'eau (vaguelettes de la pose de nage).
///
/// Anatomie : oreilles rangées 0-2, tête 3-10 (yeux tamponnés rangées 5-7,
/// colonnes 4-6 à gauche — miroir 19-c à droite), nez 8-9, cou 11, corps
/// 12-17 avec ventre crème et deux petites pattes posées dessus (rangée 13),
/// pieds 18. La queue est un node SpriteKit séparé (elle bat toute seule).
enum OtterSprites {
    /// Corps de base, sans yeux.
    private static let base: [[Int]] = [
        [0,0,0,0,6,6,0,0,0,0,0,0,0,0,6,6,0,0,0,0],
        [0,0,0,6,1,1,6,0,0,0,0,0,0,6,1,1,6,0,0,0],
        [0,0,0,6,1,4,1,6,0,0,0,0,6,1,4,1,6,0,0,0],
        [0,0,6,1,1,1,1,1,6,6,6,6,1,1,1,1,1,6,0,0],
        [0,6,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,6,0],
        [0,6,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,6,0],
        [0,6,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,6,0],
        [0,6,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,6,0],
        [0,6,1,4,2,2,2,2,2,3,3,2,2,2,2,2,4,1,6,0],
        [0,6,1,2,2,2,2,2,2,3,2,2,2,2,2,2,2,1,6,0],
        [0,0,6,1,2,2,2,2,2,2,2,2,2,2,2,2,1,6,0,0],
        [0,0,6,1,1,1,1,1,1,1,1,1,1,1,1,1,1,6,0,0],
        [0,6,1,1,1,2,2,2,2,2,2,2,2,2,2,1,1,1,6,0],
        [0,6,1,1,1,2,2,2,1,2,2,1,2,2,2,1,1,1,6,0],
        [0,6,1,1,1,2,2,2,2,2,2,2,2,2,2,1,1,1,6,0],
        [0,6,1,1,1,2,2,2,2,2,2,2,2,2,2,1,1,1,6,0],
        [0,0,6,1,1,2,2,2,2,2,2,2,2,2,2,1,1,6,0,0],
        [0,0,0,6,1,1,1,1,1,1,1,1,1,1,1,1,6,0,0,0],
        [0,0,0,0,6,1,1,6,0,0,0,0,6,1,1,6,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ]

    /// Tampon d'un point + son miroir horizontal (colonne c ↔ 19-c).
    private static func stampMirrored(_ g: inout [[Int]], _ points: [(r: Int, c: Int, v: Int)]) {
        for p in points {
            g[p.r][p.c] = p.v
            g[p.r][19 - p.c] = p.v
        }
    }

    /// Corps avec l'expression demandée tamponnée.
    static func grid(for face: OtterFace) -> [[Int]] {
        var g = base

        switch face {
        case .neutral:
            // Yeux ronds 2x2 avec un reflet en haut-GAUCHE des deux yeux
            // (source de lumière unique — un reflet miroité louche).
            stampMirrored(&g, [(6, 5, 3), (6, 6, 3), (7, 5, 3), (7, 6, 3)])
            g[6][5] = 5; g[6][13] = 5

        case .blink:
            // Yeux fermés : simple ligne foncée.
            stampMirrored(&g, [(7, 5, 3), (7, 6, 3)])

        case .happy:
            // Petits yeux plissés de contentement.
            stampMirrored(&g, [(6, 5, 3), (6, 6, 3)])

        case .curious:
            // Grands yeux écarquillés 2x3, double reflet étincelant.
            stampMirrored(&g, [
                (5, 5, 3), (5, 6, 3),
                (6, 5, 3), (6, 6, 3),
                (7, 5, 3), (7, 6, 3),
            ])
            g[5][5] = 5; g[5][13] = 5
            g[6][6] = 5; g[6][14] = 5

        case .sleepy:
            // Paupières tombantes en diagonale.
            stampMirrored(&g, [(6, 4, 3), (7, 5, 3), (7, 6, 3)])

        case .worried:
            // Sourcil relevé flottant + petits yeux bas.
            stampMirrored(&g, [(5, 6, 3), (7, 5, 3), (7, 6, 3)])
        }
        return g
    }

    /// Pose de nage : la loutre flotte sur le dos (vue de dessus, même
    /// silhouette), yeux plissés heureux, vaguelettes bleues sur les flancs
    /// et sous les pieds. La queue (node séparé) est cachée pendant la nage.
    static let swim: [[Int]] = {
        var g = grid(for: .happy)
        let ripples: [(r: Int, c: Int, v: Int)] = [
            (12, 0, 7), (13, 0, 7), (15, 1, 7), (17, 2, 7), (19, 5, 7), (19, 6, 7),
        ]
        for p in ripples {
            g[p.r][p.c] = p.v
            g[p.r][19 - p.c] = p.v
        }
        return g
    }()
}
