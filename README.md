# ZimutAdventure

Jeu d'aventure et de découverte dans les grands espaces sauvages (Ouest américain, outback australien, Grand Nord canadien). Voir le [Game Design Document](docs/GDD.md).

Moteur : **Godot 4** (GDScript) · Cibles : PC (Windows / macOS / Linux) + **Android**

## Lancer le projet

1. Télécharger [Godot 4.x](https://godotengine.org/download) (édition standard, pas la version .NET).
2. Ouvrir le dossier du projet dans l'éditeur Godot, ou lancer la scène principale :
   `scenes/world/canyon_playground.tscn` (terrain de test du canyon, région Ouest américain).
3. Jouer avec **F5** (ou ▶). Contrôles : ZQSD pour se déplacer, Maj pour courir, souris pour la caméra, Échap pour libérer la souris.

## Structure du projet

```
assets/
  landscapes/
    models/        # photos de référence (modèles pour le world design)
    shaders/       # shader du terrain (strates rocheuses)
    materials/     # matériaux Godot
  props/           # (réservé) meshes de props externes
scenes/
  player/          # scène du joueur (CharacterBody3D + caméra FPS)
  world/           # canyon_playground.tscn : scène de test jouable
scripts/
  autoload/        # InputManager, LocalizationLoader
  player/          # contrôleur du joueur
  world/           # LandscapeManager, RockGenerator, VegetationGenerator
locales/           # traductions FR/EN (CSV source)
tests/             # tests headless (SceneTree)
docs/              # GDD
```

## Build Android (APK)

Un workflow GitHub Actions (`.github/workflows/build-apk.yml`) produit un APK
**debug** et un APK **release signé** à chaque push sur `main`, sur les tags `v*`
et manuellement (Actions → Build APK).

Pour le build release signé, 3 secrets sont requis (voir
[docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md)) :
`RELEASE_KEYSTORE_BASE64`, `RELEASE_KEYSTORE_PASSWORD`.

En local :

```bash
sh tools/android/setup_android_sdk.sh   # installe le SDK Android (une fois)
sh tools/android/export_apk.sh debug    # APK debug
sh tools/android/export_apk.sh release  # APK release signé (voir docs/ANDROID_SIGNING.md)
```

## Tests (headless)

```bash
godot --headless --path . -s tests/test_landscape_generation.gd
godot --headless --path . -s tests/test_localization.gd
godot --headless --path . -s tests/test_scene_loading.gd
```

## Licence

Code : MIT. Les photos de référence dans `assets/landscapes/models/` appartiennent à leur auteur.
