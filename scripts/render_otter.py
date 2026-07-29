#!/usr/bin/env python3
"""Rendu PNG des sprites de la loutre, sans aucune dépendance.

Usage : python3 scripts/render_otter.py [sortie.png]

Génère une bande avec toutes les expressions + la pose de nage, pour retoucher
le pixel-art sans lancer l'app. La grille BASE, la palette et les tampons
d'yeux doivent rester synchronisés avec Sources/OtterIsland/Otter/
(OtterSprites.swift et PixelArt.swift).
"""
import zlib, struct, sys

# Synchronisé avec PixelArt.otterPalette.
PALETTE = {
    0: None,                # transparent
    1: (120, 84, 56),       # marron corps
    2: (222, 189, 145),     # crème ventre/museau
    3: (33, 26, 23),        # yeux / nez
    4: (242, 155, 153),     # rose joues / oreilles
    5: (250, 248, 242),     # reflet blanc
    6: (74, 48, 33),        # contour sombre
    7: (110, 175, 210),     # bleu d'eau (nage)
}

# Synchronisé avec OtterSprites.base (. = 0, B=1, C=2, D=3, P=4, W=5, O=6).
BASE_ART = """
....OO........OO....
...OBBO......OBBO...
...OBPBO....OBPBO...
..OBBBBBOOOOBBBBBO..
.OBBBBBBBBBBBBBBBBO.
.OBBBBBBBBBBBBBBBBO.
.OBBBBBBBBBBBBBBBBO.
.OBCCCCCCCCCCCCCCBO.
.OBPCCCCCDDCCCCCPBO.
.OBCCCCCCDCCCCCCCBO.
..OBCCCCCCCCCCCCBO..
..OBBBBBBBBBBBBBBO..
.OBBBCCCCCCCCCCBBBO.
.OBBBCCCBCCBCCCBBBO.
.OBBBCCCCCCCCCCBBBO.
.OBBBCCCCCCCCCCBBBO.
..OBBCCCCCCCCCCBBO..
...OBBBBBBBBBBBBO...
....OBBO....OBBO....
....................
"""

def parse(art):
    m = {'.': 0, 'B': 1, 'C': 2, 'D': 3, 'P': 4, 'W': 5, 'O': 6}
    return [[m[ch] for ch in line] for line in art.strip().splitlines()]

BASE = parse(BASE_ART)
D, W = 3, 5

def stamp(grid, points):
    g = [row[:] for row in grid]
    for (r, c, v) in points:
        g[r][c] = v
    return g

def pair(pts):
    """Un point + son miroir horizontal (colonne c <-> 19-c)."""
    return list(pts) + [(r, 19 - c, v) for (r, c, v) in pts]

# Synchronisé avec OtterSprites.grid(for:).
FACES = {
    "neutral": pair([(6,5,D),(6,6,D),(7,5,D),(7,6,D)]) + [(6,5,W),(6,13,W)],
    "blink":   pair([(7,5,D),(7,6,D)]),
    "happy":   pair([(6,5,D),(6,6,D)]),
    "curious": pair([(5,5,D),(5,6,D),(6,5,D),(6,6,D),(7,5,D),(7,6,D)])
               + [(5,5,W),(5,13,W),(6,6,W),(6,14,W)],
    "sleepy":  pair([(6,4,D),(7,5,D),(7,6,D)]),
    "worried": pair([(5,6,D),(7,5,D),(7,6,D)]),
}

# Synchronisé avec OtterSprites.swim.
SWIM = stamp(stamp(BASE, FACES["happy"]),
             pair([(12,0,7),(13,0,7),(15,1,7),(17,2,7),(19,5,7),(19,6,7)]))

def write_png(path, grid, scale=12, bg=(24, 26, 32)):
    h, w = len(grid), len(grid[0])
    rows = []
    for y in range(h * scale):
        row = bytearray([0])
        for x in range(w * scale):
            c = PALETTE.get(grid[y // scale][x // scale]) or bg
            row += bytes((*c, 255))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w*scale, h*scale, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"écrit {path} ({w}x{h} -> {w*scale}x{h*scale})")

if __name__ == "__main__":
    grids = [stamp(BASE, pts) for pts in FACES.values()] + [SWIM]
    strip = []
    for r in range(20):
        row = []
        for g in grids:
            row += g[r] + [0]
        strip.append(row)
    write_png(sys.argv[1] if len(sys.argv) > 1 else "otter_preview.png", strip)
