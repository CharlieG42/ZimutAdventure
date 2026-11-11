# VFX 2D (particules)

Textures de particules dans `particles/`, source **Kenney Particle Pack 1.1 (CC0 1.0)**
— voir [particles/LICENSE-kenney-particles.txt](particles/LICENSE-kenney-particles.txt),
miroir GitHub `Calinou/kenney-particle-pack`.

Utilisées par `scripts/vfx/particles.gd` (feu de camp : flammes + fumée + braises ;
poussière de course ; éclats de roche) avec repli procédural (disque/cône) si une
texture est absente.

Régénération : copier les PNG du pack (aucun traitement requis).

## Ciel et overlays 2D (générés, pas de source externe)

- `sky/cloud_cover.png` : couverture nuageuse tileable (bruit fractal Pillow) branchée sur
  `ProceduralSkyMaterial.sky_cover` du ciel du canyon (assombri la nuit via `sky_cover_modulate`).
- `overlays/vignette.png` : vignette radiale posée en multiply sur le HUD (`FxLayer`).
- `overlays/grain.png` : grain film subtil animé (décalage du tile toutes les ~90 ms).

Régénération : `python3 tools/generate_atmosphere_assets.py` (Pillow).
