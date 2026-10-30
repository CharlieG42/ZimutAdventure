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

## Qualité de code (leçons des revues)

Références issues de la revue de la PR #22 — niveau de qualité attendu pour toute
nouvelle contribution gameplay.

### Design des systèmes

- **Progression cumulative, pas instantanée** : un objectif de quête suit tout ce que le
  joueur a gagné depuis le début (compteur `_collected`), jamais seulement le contenu
  actuel du sac. Dépenser des ressources ne doit jamais défaire une quête. Sauvegarder
  les états ET les compteurs (`user://quests.cfg`).
- **Chaînage par prérequis** : une quête peut exiger une autre (`requires`) ; elle reste
  LOCKED tant que la précédente n'est pas terminée. Ne jamais tout activer d'office.
- **Sauvegarder chaque système dans son fichier** : `user://inventory.cfg`,
  `user://quests.cfg`, `user://structures.cfg`. Un autoload = une persistance.
- **API riche des managers** : le journal et le HUD ne fouillent pas les dictionnaires
  internes ; ils appellent `get_progress()`, `get_missing()`, `get_reward()`,
  `get_tracked()`, `get_recipes_in_category()`… Prévoir les accesseurs dès la conception.
- **Récompenses visibles** : les quêtes offrent des ressources (`reward`), affichées dans
  la carte de quête ET le toast de fin. Elles aident à enchaîner les quêtes suivantes.

### UI / HUD

- **Mise à jour en direct** : les panneaux se connectent aux signaux (`item_added`,
  `quest_state_changed`, `quest_progress_changed`) et se rafraîchissent
  `call_deferred()` — pas seulement à l'ouverture.
- **Retour visuel riche** : cartes avec stylebox (fond + bordure), barres de progression,
  couleurs sémantiques (vert = suffisant, rouge = manquant, BBCode `[color=#...]` dans
  RichTextLabel pour le détail des ingrédients `2/4 bois`).
- **Adaptation tactile/écran** : `_fit_to_viewport()` avec `clampf` (min/max), défilement
  `ScrollContainer` pour le contenu long, boutons ≥ 56 px de haut, `focus_mode = NONE`,
  fermeture par `ui_cancel` via `_unhandled_key_input` + `set_input_as_handled()`.
- **Ne pas recouvrir le HUD** : un panneau plein écran réserve la place des barres
  existantes (calcul de `_map_rect()` avec marges haut/bas) et place son bouton Fermer
  hors des zones occupées.
- **Carte lisible en plein soleil** : formes distinctes par type de ressource (cercle,
  carré, losange, triangle, maison), pas seulement des couleurs ; contour foncé sous
  chaque repère ; ombrage de relief (dérivées first-order des hauteurs) pour que les
  falaises se lisent ; texture carrée alignée pixel-par-pixel avec les repères
  (ne jamais étirer `draw_texture_rect` sur un rect non carré).
- **Rafraîchissement throttlé** : `queue_redraw()` à intervalle fixe (période 0.2 s),
  pas à chaque frame quand la carte est ouverte.

### Gameplay / monde

- **Animaux crédibles** : machine à états (marche / broutage), détection de blocage
  (`get_real_velocity()` vs vitesse voulue pendant STUCK_SECONDS), gravité correcte
  (accélération + vitesse terminale, PAS d'anti-gravité permanente), téléportation de
  secours sous y < -80, retour au territoire si trop loin, modèles et démarches par
  espèce (cerf/lièvre), animation construite en code (jambes, cou, tête).
- **Constructions posables** : validation de pente (échantillons autour du point,
  MAX_SLOPE), limite du nombre, collision pleine, sauvegarde/rechargement, interactions
  contextuelles (lit = repos ; abri = dormir uniquement la nuit, réveil à 7 h via
  `DayNightCycle.set_hour`).
- **Corriger les bugs à la racine** : « Premiers outils » visait `item_plank` qui
  n'existait pas — vérifier que chaque objectif de quête correspond à un id d'item ou de
  recette réellement obtensible dans le jeu.

### Tests headless (pièges rencontrés)

- **Isoler les effets de bord** : le vrai autoload QuestManager délivre des récompenses
  qui faussent les autres tests (qui comptent l'inventaire exact). Guarder avec
  `DisplayServer.get_name() != "headless"` ou `_grant_rewards`, et exposer
  `enable_rewards_for_test()` quand un test en a besoin.
- **La sauvegarde locale masque les bugs de CI** : `user://...` persiste entre les runs
  locaux ; toujours `clear_for_test()` (qui coupe aussi `_autosave`) en début de test.
- **Facteur commun de setup** : `_ensure(name, path)` qui réutilise l'autoload s'il
  existe, sinon l'instancie — un seul pattern pour tous les tests d'un fichier.
- **`class_name` = cache global** : après l'ajout d'un nouveau `class_name`, relancer
  `godot --headless --path . --import` avant les tests, sinon `Identifier not declared`
  dans les scripts qui le référencent (la CI fait l'import, pas la machine locale).
- **Tester la chaîne complète** : déblocage en cascade, récompense créditée, progression
  affichée avant la fin, dépense qui ne défait pas une quête.
