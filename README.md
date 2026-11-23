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
| Viser à l'arc | Clic droit maintenu | Visée automatique quand l'arc est équipé |
| Sac / journal | C | Bouton Journal |
| Vue 1re / 3e personne | V | Bouton 1P/3P |

La course consomme de l'endurance (barre discrète en bas) ; la boussole en haut suit le cap du joueur (Nord = -Z). Option `sprint_at_full_tilt` sur le joueur pour désactiver la course automatique.

### Objets et environnement

- **Ramasser** : des pierres et des bûches de bois jonchent le canyon (E ou bouton interaction). Le sac (bouton Journal / touche C) liste l'inventaire, sauvegardé automatiquement.
- **Feu de camp** : près du départ, alimentez-le avec 4 bûches pour l'allumer (la lumière grandit à chaque bûche). Une fois allumé, « Se reposer » restaure l'endurance.
- **Pancarte** : lisez le panneau au départ pour un message d'ambiance (affiché en toast, traduit FR/EN).
- **Rochers cassables** : environ 25 petits rochers dans le canyon ont une vraie collision (impossible de les traverser) et se cassent à l'interaction en lâchant 2 à 4 pierres ramassables, avec éclats animés.
- **Premiers pas** : au premier lancement, six consignes guident le joueur (marcher, regarder, ramasser, ouvrir le journal puis la carte, suivre la boussole), avec des textes tactiles ou clavier. « Passer » les arrête ; Journal → Réglages → « Revoir le tutoriel ».
- **Contrôles tactiles** : stick de déplacement flottant dans toute la moitié gauche, glisser caméra partout ailleurs (plus de zone morte), pouce gauche et droit simultanés ; Journal → Réglages → « Sensibilité de la caméra ».
- **Dépeçage** : un gibier ou un prédateur abattu laisse sa dépouille 2 minutes ; « Dépecer » donne la viande (et la peau du cerf, du loup, du coyote). Rien n’arrive plus automatiquement dans le sac.
- **Sons** : pas selon le sol (sable, herbe, neige, eau ; sabots à cheval), vent qui forcit la nuit, par mauvais temps et en hauteur, pluie, rivière qu'on entend en s'approchant, oiseaux le jour, grillons et hurlements lointains la nuit, cris des animaux placés dans l'espace (et de temps en temps spontanés), coups de hache. Enregistrements CC0 (Kenney, Ninja Adventure, Freesound, OpenGameArt) ; voix synthétisées pour les animaux sans enregistrement libre. Crédits : `assets/audio/CREDITS.md`.
- **Animaux animés** : cerfs, loups, coyotes, vaches, moutons, chevaux et chiens sont de vrais modèles 3D animés (Quaternius, CC0) — repos, broutage, marche, galop, morsure, chute. Le lièvre, la chèvre et la poule gardent leur modèle simple.
- **Froid et chaleur** : la température ressentie (affichée à côté de l'heure) dépend de la saison, de l'heure, de la météo, de l'altitude et d'être mouillé. Sous 6 °C la jauge de Chaleur baisse — surtout les nuits d'automne et d'hiver ; vide, elle coûte de la santé. Un feu allumé (moins de 7 m), un abri et la cape de fourrure réchauffent ; la rivière et la pluie mouillent. Au-delà de 32 °C (après-midi d'été) on a plus soif.
- **Zones et rivière** : le canyon se partage en quatre zones — Plaine aux Cactus (départ), Pinède des Geais (collines boisées au nord-ouest), Mesas Rouges (plateaux et hoodoos au sud-est) et Rivière du Vieux Gué, qui serpente d'un lac à l'autre. Le décor suit les zones (pins en pinède, cactus en plaine, herbe et fleurs sur les berges), le nom de la zone s'affiche en y entrant et sur la carte. La rivière se traverse à gué (on y marche plus lentement) et on peut y boire partout (E au bord de l'eau).
- **Carte** (bouton Carte / touche M) : vue plein écran du canyon avec topographie coloriée par altitude, position du joueur (point bleu + cap) et ressources (pierres, bois, rochers cassables).
- **Carnet d'observation** (Journal → Carnet) : 24 entrées de faune, flore et paysages. Regardez de près un animal, une plante ou une formation rocheuse et elle se note toute seule ; un poisson pêché ou un lieu atteint aussi. Les entrées inconnues donnent un indice ; chaque observation rapporte de l'expérience et des paliers (6, 12, 18, 24) offrent des récompenses. Quête « Carnet de naturaliste » (8 observations).
- **Repères et orientation** : sur la carte, touchez un endroit puis « Poser un repère » (8 au plus ; touchez un repère pour le retirer). La carte donne son azimut et sa distance, et un fanion jaune glisse sur la boussole pour indiquer son cap. Cinq quêtes d'exploration s'appuient dessus (rivière, repère, pinède, plateau des mesas, source), avec des consignes à l'azimut depuis le panneau de départ. Réglages → « Mini-carte » : la désactiver donne un mode explorateur (boussole et carte seulement).
- **Journal de quêtes** (bouton Journal / touche C) : onglets Quêtes (objectifs de collecte avec progression automatique), Fabrication et Sac. Cinq quêtes enchaînées (pierres, feu, hache, arc, abri) avec barres de progression et récompenses en ressources ; la progression est cumulative et sauvegardée, et l'objectif en cours s'affiche sous le cap.
- **Fabrication / construction** : recettes (hache en pierre, arc de chasse, lit de camp, abri) consommant les ressources du sac ; base du futur mode de construction d'habitation.
- **Constructions** : le lit de camp et l'abri fabriqués se posent depuis le Sac (bouton Poser, devant le joueur, terrain plat uniquement). Le lit rétablit l'endurance, l'abri permet de dormir la nuit jusqu'à 7 h. Elles sont sauvegardées (`user://structures.cfg`) et apparaissent sur la carte, avec le feu de camp.
- **Animaux inoffensifs** : 6 animaux (cerfs et lièvres) errent dans le canyon, broutent et fuient le joueur s'il s'approche trop.
- **Faim et soif** : deux jauges (barres discrètes sous l'endurance) décroissent avec le temps — plus vite en courant. Vides, elles ralentissent la récupération d'endurance ; les deux vides bloquent la course. Buvez aux sources du canyon (E, avec remplissage), mangez la viande cuite depuis le Sac (bouton Manger). Sauvegarde automatique.
- **Chasse et cuisson** : fabriquez l'arc de chasse et des flèches (x4 avec 1 bois + 1 pierre), visez avec le clic droit maintenu (zoom + tir tendu, moins de dispersion) ou le bouton « Viser » (tactile) : en visée, déplacer le viseur ne fait plus tourner le personnage ; tirez avec clic gauche / bouton « Tirer » (appui bref = tir rapide correct, appui long = tir tendu). Une proie touchée fuit puis lâche de la viande crue ; cuisez-la sur un feu de camp plein (« Cuire la viande »). Chaîne de quêtes : première chasse → repas chaud.
- **Corrections tactile** : le bouton « Frapper » (hache équipée) abat l'arbre devant soi (et se distingue d'« Action »), le panneau Déplacer/Tourner/Poser/Annuler se place au-dessus de la barre Journal / 1P-3P, et un appui sur la mini-carte ne la referme plus aussitôt (appui doublé toucher + souris).
- **Sifflet, couteau, palissades** : un bouton « Siffler » (touche H) apparaît dans la barre du bas dès qu'un cheval ou un chien est apprivoisé : ils accourent vers vous. Le couteau (2 pierres + 1 bois, niveau 1) se fabrique et donne un morceau de viande de plus au dépeçage. Les tronçons de palissade se visent et se déplacent comme les meubles.
- **Parties et menu de démarrage** : 3 parties au maximum (`scripts/player/save_slots.gd`, un dossier `user://saves/slotN/` par partie). Au lancement (`scenes/main_menu.tscn`) : jouer ou supprimer une partie, ou « Nouvelle partie » sur un emplacement libre (choix homme / femme, nom, apparence, puis l'aventure démarre). Le nom et l'apparence restent modifiables en cours de partie (journal > réglages). L'ancienne sauvegarde devient la partie 1. Le journal (réglages) propose « Retour au menu principal » : la partie est sauvegardée puis on peut en choisir une autre.
- **Ranch et abri évolutif** : l'enclos est interactif (« Rassembler le bétail » : vaches, moutons, chèvres et poules apprivoisés des environs rejoignent l'enclos en marchant, dans la limite des places ; « Libérer le bétail » les fait ressortir). Il s'améliore en 3 niveaux (6 / 10 / 16 places, abreuvoir, foin et appentis) et on peut en construire plusieurs. L'abri s'agrandit aussi à chaque niveau (intérieur 3,0×2,8 → 4,6×4,0 → 6,2×5,4 m, avec foyer, table et tabourets au niveau 3) ; l'agrandissement est refusé si une construction gêne.
- **Animaux apprivoisés** : le Journal a un onglet « Animaux » (compteur par espèce, bêtes en enclos, chien qui suit ou reste) et trois succès d'élevage (3, 8 puis 15 animaux apprivoisés). Le chien se rappelle au sifflet même à cheval ; le cavalier est assis derrière le garrot et l'invite d'action s'affiche au-dessus du réticule, sans masquer le personnage. L'enclos se déplace comme les autres constructions (ses bêtes le suivent), et les animaux, cheval compris, n'entrent pas dans l'abri.
- **Personnage low-poly** : homme ou femme, modèles GLB modulaires V5 (`assets/characters/zimut_*.glb`, chargés par `scripts/player/glb_hero.gd`, squelette Mixamo commun, matériaux recolorés par le profil) ; le personnage construit en code (`scripts/player/lowpoly_hero.gd`) sert de secours. Animations posées os par os (marche, course, saut, hache, arc, cheval) et ses outils en main. Écran de création au premier lancement (teint, coiffure, couleurs de cheveux, tunique et pantalon), modifiable ensuite dans le journal > réglages. Les vêtements fabriqués (chapeau de paille, bottes de peau, sac à dos, cape de fourrure) apparaissent sur le personnage. Profil dans `user://character.cfg` ; l'ancien modèle Mixamo reste en secours.

Régénérer les images du HUD : `python3 tools/generate_ui_assets.py` puis `godot --headless --path . -s tools/make_hud_theme.gd`. Icônes d'items/outils (sac, hotbar) : `python3 tools/generate_item_icons.py` (Pillow). Atmosphère (nuages du ciel, vignette, grain film) : `python3 tools/generate_atmosphere_assets.py` (Pillow). Empreinte de pas (traces au sol) : `python3 tools/generate_footprint.py` (Pillow). Note : Godot 4.7 possède une classe native `VirtualJoystick`, notre stick s'appelle donc `TouchStick`.

Régénérer les props GLB (Kenney CC0 + ruines composées) : `python3 tools/make_glb_props.py all --kenney-root <checkout du miroir github.com/shorepine/kenney>` — voir [assets/props/README.md](assets/props/README.md).
Régénérer les cactus saguaro : `python3 tools/make_cactus_glb.py all` (stdlib pur, aucune dépendance).

## Structure du projet

```
assets/
  landscapes/
    models/        # photos de référence (modèles pour le world design)
    shaders/       # shader du terrain (strates rocheuses)
    materials/     # matériaux Godot
  props/           # meshes GLB externes (Kenney CC0) + ruines composées — voir assets/props/README.md
  vfx/             # textures de particules (Kenney Particle Pack CC0) — voir assets/vfx/README.md
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
