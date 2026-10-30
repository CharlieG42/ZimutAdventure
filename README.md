# ZimutAdventure

Jeu d'aventure et de découverte dans les grands espaces sauvages (Ouest américain, outback australien, Grand Nord canadien). Voir le [Game Design Document](docs/GDD.md).

Moteur : **Godot 4** (GDScript) · Cibles : PC (Windows / macOS / Linux) + **Android**

## Lancer le projet

1. Télécharger [Godot 4.x](https://godotengine.org/download) (édition standard, pas la version .NET).
2. Ouvrir le dossier du projet dans l'éditeur Godot, ou lancer la scène principale :
   `scenes/world/canyon_playground.tscn` (terrain de test du canyon, région Ouest américain).
3. Jouer avec **F5** (ou ▶). Contrôles : ZQSD pour se déplacer, Maj pour courir, souris pour la caméra, Échap pour libérer la souris.

### Contrôles

| Action | Clavier / souris | Tactile (Android) |
|---|---|---|
| Se déplacer | ZQSD / flèches | Stick gauche (vitesse proportionnelle à l'inclinaison) |
| Courir | Maj | Stick à fond (course automatique), ou bouton course |
| Regarder | Souris | Glisser sur l'écran, ou stick droit |
| Sauter | Espace | Bouton saut |
| Interagir | E | Bouton interaction (s'allume face à un objet) |
| Sac / journal | C | Bouton Journal |
| Vue 1re / 3e personne | V | Bouton 1P/3P |

La course consomme de l'endurance (barre discrète en bas) ; la boussole en haut suit le cap du joueur (Nord = -Z). Option `sprint_at_full_tilt` sur le joueur pour désactiver la course automatique.

### Objets et environnement

- **Ramasser** : des pierres et des bûches de bois jonchent le canyon (E ou bouton interaction). Le sac (bouton Journal / touche C) liste l'inventaire, sauvegardé automatiquement.
- **Feu de camp** : près du départ, alimentez-le avec 4 bûches pour l'allumer (la lumière grandit à chaque bûche). Une fois allumé, « Se reposer » restaure l'endurance.
- **Pancarte** : lisez le panneau au départ pour un message d'ambiance (affiché en toast, traduit FR/EN).
- **Rochers cassables** : environ 25 petits rochers dans le canyon ont une vraie collision (impossible de les traverser) et se cassent à l'interaction en lâchant 2 à 4 pierres ramassables, avec éclats animés.
- **Carte** (bouton Carte / touche M) : vue plein écran du canyon avec topographie coloriée par altitude, position du joueur (point bleu + cap) et ressources (pierres, bois, rochers cassables).
- **Journal de quêtes** (bouton Journal / touche C) : onglets Quêtes (objectifs de collecte avec progression automatique), Fabrication et Sac. Cinq quêtes enchaînées (pierres, feu, hache, arc, abri) avec barres de progression et récompenses en ressources ; la progression est cumulative et sauvegardée, et l'objectif en cours s'affiche sous le cap.
- **Fabrication / construction** : recettes (hache en pierre, arc de chasse, lit de camp, abri) consommant les ressources du sac ; base du futur mode de construction d'habitation.
- **Constructions** : le lit de camp et l'abri fabriqués se posent depuis le Sac (bouton Poser, devant le joueur, terrain plat uniquement). Le lit rétablit l'endurance, l'abri permet de dormir la nuit jusqu'à 7 h. Elles sont sauvegardées (`user://structures.cfg`) et apparaissent sur la carte, avec le feu de camp.
- **Animaux inoffensifs** : 6 animaux (cerfs et lièvres) errent dans le canyon, broutent et fuient le joueur s'il s'approche trop.

Régénérer les images du HUD : `python3 tools/generate_ui_assets.py` puis `godot --headless --path . -s tools/make_hud_theme.gd`. Note : Godot 4.7 possède une classe native `VirtualJoystick`, notre stick s'appelle donc `TouchStick`.

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
