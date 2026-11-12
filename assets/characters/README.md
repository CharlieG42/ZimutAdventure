# Personnage joueur

- `hero.glb` : personnage généré avec Meshy, rigué et animé (marche) avec Mixamo.
  Retraité pour le mobile : maillage ramené de 186 000 à 22 000 triangles (UV conservés,
  poids de peau reportés), texture de couleur en 1024 px, matériau mat, animation
  renommée `walk` (boucle de 1,03 s, sur place). Taille 1,7 m.
- Une seule animation pour l'instant. Les autres animations Mixamo (repos, course, saut…)
  s'ajouteront ici ; voir `scripts/player/hero_model.gd`.
- Si le fichier est absent ou invalide, le joueur garde son ancien corps en pièces rigides.
- La texture extraite à l'import (`hero_*.png`) est régénérée par Godot : elle est ignorée par git.
