"""Texture de bruit raccordable (256 x 256, RVBA) pour le shader du terrain.

Chaque canal remplace un bruit calculé par pixel dans le shader (4 hachages à base de
sinus chacun) par une seule lecture de texture, bien moins chère sur mobile :
  R : bruit de valeur, 32 cellules par côté   -> noise(p)  ~ texture(p / 32).r
  G : fbm 4 octaves, 8 cellules de base       -> fbm(p)    ~ texture(p / 8).g
  B : bruit de valeur indépendant, 32 cellules
  A : bruit de valeur indépendant, 64 cellules (détail fin)
Usage : python3 tools/generate_noise_texture.py assets/landscapes/textures/terrain_noise.png
"""
import sys
import numpy as np
from PIL import Image

SIZE = 256

def value_noise(cells, seed):
    rng = np.random.default_rng(seed)
    grid = rng.random((cells, cells))
    coords = np.arange(SIZE) * cells / SIZE
    i0 = np.floor(coords).astype(int)
    f = coords - i0
    f = f * f * (3.0 - 2.0 * f)
    i1 = (i0 + 1) % cells
    gx0, gx1 = np.meshgrid(i0, i0, indexing="xy"), np.meshgrid(i1, i1, indexing="xy")
    fx, fy = np.meshgrid(f, f, indexing="xy")
    a = grid[gx0[1], gx0[0]]
    b = grid[gx0[1], gx1[0]]
    c = grid[gx1[1], gx0[0]]
    d = grid[gx1[1], gx1[0]]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def fbm(base, seed):
    value = np.zeros((SIZE, SIZE))
    amplitude = 0.5
    for octave in range(4):
        value += amplitude * value_noise(base * 2 ** octave, seed + octave)
        amplitude *= 0.5
    return value

def main(path):
    channels = [value_noise(32, 11), fbm(8, 23), value_noise(32, 37), value_noise(64, 53)]
    data = np.stack([np.clip(c * 255.0 + 0.5, 0, 255).astype(np.uint8) for c in channels], axis=-1)
    Image.fromarray(data, "RGBA").save(path, optimize=True)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/landscapes/textures/terrain_noise.png")
