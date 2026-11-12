# Personnage joueur

- `hero.glb` : personnage généré avec Tripo3D, rigué et animé (marche) avec Mixamo.
  Export Godot : texture réduite à 1024 px, animation renommée `walk`, échelle ×100
  (Mixamo livre en centimètres) intégrée au nœud racine.
- Animation unique pour l'instant (`walk`, en place, boucle de 0,97 s). Les autres
  animations Mixamo (repos, course, saut…) s'ajouteront ici ; voir `scripts/player/hero_model.gd`.
- Si le fichier est absent ou invalide, le joueur garde son ancien corps en pièces rigides.
