# Props 3D externes (GLB)

Maillages `.glb` utilisés par le monde, chargés par `scripts/world/glb_prop_library.gd`
(Godot importe les GLB nativement). Si un fichier est absent ou non importé, le jeu
retombe automatiquement sur les maillages procéduraux (`RockGenerator`,
`VegetationGenerator`, colonnes/blocs des sites).

## Sources et licence

- `kenney/nature/*.glb` et `kenney/castle/*.glb` : kits **Nature** et **Castle** de
  [Kenney](https://kenney.nl), via le miroir GitHub
  [shorepine/kenney](https://github.com/shorepine/kenney) (4 812 modèles glTF).
  Licence **CC0 1.0** — voir [LICENSE-kenney.txt](LICENSE-kenney.txt). Créditer Kenney
  n'est pas requis mais apprécié.
- `kenney/castle/Textures/colormap.png` : texture référencée (URI relatif) par les
  pièces du Castle Kit, copiée à côté des ruines composées.
- `kenney/castle/ruin_a.glb` / `ruin_b.glb` : **composés maison** à partir de pièces du
  Castle Kit (tour, murs, engins de siège démantelés), teintés grès ocre.
- `generated/cactus_saguaro_{a,b,c}.glb` : saguaros générés en Python pur
  (`tools/make_cactus_glb.py`, côtes, bras, couleurs dans les sommets) ; même pour
  `generated/rock_{1..6}.glb` (`tools/make_rock_glb.py`, rochers de grès).

## Régénération

Depuis la racine du projet, avec un checkout sparse du miroir Kenney :

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/shorepine/kenney /tmp/kenney
cd /tmp/kenney && git sparse-checkout set 3d/nature 3d/castle
cd -  # retour à la racine du projet
python3 tools/make_glb_props.py all --kenney-root /tmp/kenney
python3 tools/make_glb_props.py inspect assets/props/kenney/nature/pine_tall_a.glb
python3 tools/make_cactus_glb.py all   # saguaros -> assets/props/generated/
```

`tools/make_glb_props.py` (stdlib Python pure, pas de Blender) :
- `vendor` : copie les GLB nature listés dans `NATURE_SPEC`, normalisés à une hauteur
  cible en mètres avec l'origine au sol (min.y = 0, centré en x/z) ;
- `compose` : fusionne les pièces castle de `RUIN_SPEC` en une scène GLB par ruine
  (un buffer, nœuds transformés, textures dédupliquées par URI, teinte baseColorFactor).

## Props enregistrés

| prop_id | variantes | usage |
|---|---|---|
| `pine` | 9 | pins du canyon (MultiMesh) |
| `boulder` | 10 | rochers du sol (MultiMesh, collision sphère) |
| `shrub` | 4 | buissons |
| `grass` | 3 | herbes sèches |
| `flowers` | 9 | fleurs |
| `cactus` | 5 (2 Kenney + 3 saguaros générés) | cactus |
| `ruin` | 2 | sites « ruine » (scène instanciée, collision boîte par maillage) |

Hoodoos, buttes et agaves restent procéduraux (pas d'équivalent GLB satisfaisant).
