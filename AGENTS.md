# Conventions de travail — ZimutAdventure

Instructions pour les agents (IA) travaillant sur ce dépôt. Godot 4 (GDScript), cibles PC + Android.

## Flux de livraison

1. Travailler sur une branche `vibe/<slug>` (jamais directement sur `main`).
2. Ouvrir une PR draft vers `main` avec un corps en français (Summary / Verification).
3. Après validation (voire CI verte), fusionner la PR **via merge commit** (`--no-ff`, message `Merge pull request #N from CharlieG42/vibe/<slug>`).
   - Si les outils de fusion sont indisponibles, faire l'équivalent localement : `git merge --no-ff origin/vibe/<slug> -m "Merge pull request #N ..."` puis `git push origin main`.
4. Ne jamais forcer un push sur `main` ni supprimer une branche de PR ou remplacer une PR existante.

## Livraison des APK

- Le workflow `.github/workflows/build-apk.yml` publie les APK **dans la release `build-latest`** à chaque push sur `main` (pas dans les artefacts, régulièrement purgés par quota).
- Cette release doit rester **version stable (Latest), jamais pre-release** (`prerelease: false`) : c'est le point de téléchargement visible depuis la page du dépôt.
- Après chaque fusion, vérifier que le run « Build APK (Android) » lié au push sur `main` passe, puis confirmer que `gh api repos/.../releases/latest` renvoie `build-latest` avec `ZimutAdventure-debug.apk` et `ZimutAdventure-release.apk` à jour.

## Tests

- Toute modification passe la suite complète avant commit : `sh tests/run_all.sh godot` (14+ tests headless, tous doivent PASS).
- Un test headless doit être robuste en mode `-s` : les autoloads peuvent être absents selon la version ; instancier `Inventory`/`Sfx` manuellement si `root.get_node_or_null("...")` est nul.
- `ConeMesh` n'existe pas en Godot 4.7 : utiliser `CylinderMesh` avec `top_radius` faible pour un cône.

## Interactions / gameplay

- Les objets interactifs dérivent de `Interactable` (`scripts/interaction/interactable.gd`) : couche de collision 4 pour l'Area3D d'interaction, invite traduite via `prompt_text` + clé `locales/translations.*.csv` (FR **et** EN, toujours les deux).
- Tout prop solide porte un `StaticBody3D` sur la couche 1 (celle du terrain) pour bloquer le joueur.
- L'inventaire (`Inventory`) persiste dans `user://inventory.cfg` ; les items ramassables émettent un toast via le HUD (groupe `hud`).

## Traductions

- Les fichiers sources sont `locales/translations.en.csv` et `locales/translations.fr.csv` (pas `en.csv`/`fr.csv`). Toute nouvelle clé de traduction doit être ajoutée aux deux.
