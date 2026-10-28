# ZimutAdventure — Game Design Document

> Jeu d'aventure et de découverte dans les grands espaces sauvages du monde.
> Moteur : **Godot 4** · Cible : PC (Windows / macOS / Linux) + **Android** · Solo

---

## 1. Concept en une phrase

Explorer à pied et à cheval des territoires sauvages immenses — Ouest américain, outback australien, contrées canadiennes — en s'orientant à la carte et au compas, en survivant aux éléments et en découvrant les secrets de chaque terre.

Le nom **Zimut** vient de l'**azimut** : l'orientation est au cœur du jeu. On ne se téléporte pas, on *chemine*.

## 2. Univers et ton

- **Époque** : fin du XIXe siècle, ère des explorateurs (1870–1900). Pas de technologie moderne : cheval, carte, boussole, feu de camp, fusil de chasse.
- **Ton** : contemplatif et rude. La beauté des horizons, mais aussi la faim, le froid, la soif, la nuit qui tombe.
- **Aucune magie** : réalisme léger, pas de fantastique (pour l'instant — un mode « légendes » pourra raconter des mythes locaux en toile de fond).
- Le joueur incarne un **explorateur solitaire** (personnage personnalisable léger : sexe, tenue de départ) au service de sa propre curiosité — et parfois d'une quête : retrouver un disparu, cartographier une vallée inconnue, photographier (croquer) une espèce rare.

## 3. Boucle de gameplay

```
Préparer l'expédition → Partir avec un chargement limité → Explorer, s'orienter,
survivre → Découvrir (sites, faune, ruines, rencontres) → Rentrer au camp /
village pour vendre, réparer, se soigner → Débloquer de nouvelles régions et
équipement → Repartir plus loin
```

Chaque expédition est une **session de jeu autonome** : on choisit sa destination sur la carte du monde, on prépare son sac (poids limité), et on part. La mort n'est pas un « game over » brutal : on est ramené au dernier camp inconscient, en ayant perdu une partie de son équipement.

## 4. Mécaniques principales

### 4.1 Déplacement et voyage
- **À pied** : lent, silencieux, peu fatigant. Permet d'approcher la faune.
- **À cheval** : rapide sur terrain ouvert, mais le cheval a besoin d'eau et de repos, et s'effraie (bruits, prédateurs).
- **Véhicules rudimentaires** selon les régions : mulet, canoë (rivières canadiennes), chameau (désert, si région ajoutée).
- **Fatigue** : courir ou galoper épuise ; il faut gérer son allure.

### 4.2 Orientation (mécanique signature)
- Pas de minimap moderne ni de marqueur GPS. Le joueur dispose de :
  - une **boussole** (needle qui pointe le nord magnétique),
  - une **carte du monde** (ouverte avec la touche carte) sur laquelle il peut **placer des repères** lui-même (azimut + distance estimée),
  - le **soleil et les étoiles** comme repères naturels,
  - un **journal de terrain** où il note ses observations.
- Se perdre est **réel et punitif** : errer sans repères épuise, désoriente, et peut mener à la déshydratation.
- Le sentiment de réussite : retrouver son camp *grâce à ses propres notes* après trois jours de marche.

### 4.3 Survie légère
- **Soif** : l'eau est la ressource critique. Rivières, puits, collecte d'eau de pluie. Déshydratation = hallucinations (effet visuel), puis évanouissement.
- **Faim** : chasse, pêche, cueillette, ration de voyage. Manger cru ou mal cuit = risque de maladie.
- **Température** : nuits glaciales canadiennes, chaleur du désert. Le **feu de camp** et les vêtements adaptés sont vitaux.
- **Météo** : pluie, neige, tempête de sable, orage. La météo change la visibilité et la difficulté du voyage.
- **Santé** : blessures (chute, morsure, chute de cheval), maladies simples, soin avec bandages et plantes médicinales.

### 4.4 Faune et flore
- **Observation** : jumelles (outil), carnet de croquis. Identifier une espèce pour la première fois la « débloque » dans le bestiaire du journal.
- **Comportement réaliste** : herbivores craintifs, prédateurs territoriaux (loups, pumas, dingos, ours). Certains animaux fuient le feu et le bruit, d'autres non.
- **Chasse** : fusil + traque (empreintes, excréments, bruits). Tirer attire les prédateurs et alerte le gibier alentour.
- **Flore** : plantes comestibles, médicinales, toxiques. Cueillette saisonnière.

### 4.5 Camps, repos et préparation
- **Campement** : installer une tente, allumer un feu, cuisiner, dormir (la nuit accélère le temps et restaure la fatigue).
- **Poids du sac** : chaque objet a un poids. Trop chargé = déplacement ralenti, fatigue accélérée. Choix cornéliens : l'antidote ou la corde ?
- **Préparation d'expédition** : depuis un camp ou un village, choisir itinéraire, monture, équipement, ration de nourriture et d'eau estimée pour la durée.

### 4.6 Rencontres et narration environnementale
- **PNJ** : trappeurs, guides autochtones (représentés avec respect et recherche documentaire), voyageurs, ermites, scientifiques.
- **Quêtes** : missions données par les PNJ (retrouver un troupeau, escorter un convoi de chariots, étudier une espèce), résolues par l'exploration, pas par des marqueurs.
- **Narration environnementale** : ruines de fermes abandonnées, carcasses, camps de mineurs, pétroglyphes — chaque site raconte une histoire lisible sans texte.
- **Événements aléatoires** : attaque de loups, cheval blessé, tempête soudaine, découverte d'une source inconnue.

### 4.7 Progression
- **Réputation** par région : aide les habitants, cartographie la zone, leur ramène des spécimens → débloque accès à de meilleurs guides, montures, acheteurs.
- **Compétences** : orientation (repères plus précis), survie (moins de consommation d'eau), chasse (traque plus efficace), équitation (cheval moins fatigué).
- **Déblocage de territoires** : chaque grande région est verrouillée au début (carte partielle, passages gardés) et s'ouvre par la progression ou une quête.
- **Collection** : bestiaire, herbier, carte complétée, sites découverts — consultables dans le journal.

## 5. Les régions (biomes)

| Région | Inspiration | Spécificités | Faune emblématique |
|---|---|---|---|
| **Ouest américain** (région de départ) | Canyon, mesas, désert de Sonora, Rocheuses | Chaleur, canyons, rivières asséchées, ruines minières | Puma, coyote, vautour, serpent à sonnette, bison (troupeaux) |
| **Outback australien** | Désert rouge, bush, eucalyptus | Chaleur extrême, très peu d'eau, distances énormes | Dingo, kangourou, émeu, serpent taipan, crocodile (nord) |
| **Contrées canadiennes** | Toundra, forêt boréale, lacs, montagnes | Froid, neige, loups, aurores boréales, canoë | Ours noir/grizzly, loup, orignal, castor, caribou |
| *(DLC/extension)* Patagonie | Steppes, Andes australes | Vent violent, guanacos, condors | Guanaco, condor, puma |
| *(DLC/extension)* Sahara | Dunes, oasis | Navigation aux étoiles, chameaux, chaleur extrême | Dromadaire, fennec, vautour |

Chaque région = **une grande carte ouverte** (plusieurs dizaines de km² en jeu, représentées à échelle réduite) avec points d'intérêt procéduralement placés autour d'un squelette de contenu authored.

## 6. Interface et contrôles

### 6.1 PC (clavier/souris + manette)
- ZQSD / stick gauche : déplacement
- Maj : courir (à pied) / galop (à cheval)
- E : interagir
- Tab : inventaire
- M : carte du monde
- C : journal (bestiaire, carte, notes)
- B : boussole rapide (azimut actuel)
- Clic droit : observer avec les jumelles
- V : basculer entre vue 1ère personne et vue 3ème personne (caméra dans le dos du personnage)

### 6.2 Android (tactile)
- **Deux sticks virtuels toujours visibles** : coin bas-gauche pour le déplacement, coin bas-droit pour la caméra.
- La caméra peut aussi être bougée en glissant le doigt n'importe où sur l'écran (hors des sticks).
- Bouton **vue** (1ère / 3ème personne) : en 3ème personne, la caméra suit le personnage dessiné par le dessus.
- Boutons contextuels (interagir, inventaire, carte, journal) en overlay.
- Carte du monde et journal adaptés au tactile (pinch-to-zoom sur la carte).
- Mode **portrait déconseillé** : jeu conçu en paysage ; l'interface s'adapte mais le paysage est recommandé.
- Pas de pub, pas de micro-transactions.

## 7. Direction artistique

- **Style visuel** : low-poly stylisé avec éclairage soigné (inspiration *Firewatch*, *The Long Dark* pour l'ambiance). Performant sur mobile.
- **Palette** : ocres et rouges (déserts), bleus acier et blancs (Canada), rouges profonds et verts d'eucalyptus (Australie).
- **Ambiance sonore** : vent omniprésent, bruissements, cris d'animaux au loin, musique minimaliste (guitare, harmonica) qui entre et sort selon l'intensité.
- **Cycle jour/nuit complet** avec aube/crépuscule marqués, nuits étoilées navigables, aurores boréales au Canada.

### 7.1 Références photographiques

Les photos de référence (prises par l'auteur) sont stockées dans `assets/landscapes/models/` :

| Fichier | Sujet | Usage |
|---|---|---|
| `canyon_panorama_01.heic` | Panorama falaises rouges, mesas à sommet plat | Composition du terrain, horizon |
| `canyon_strata_01.jpg` | Parois stratifiées rouge/orange | Shader terrain (strates), palette ocre/rouge |
| `canyon_hoodoos_pines_01.jpg` | Hoodoos + pins dispersés | Props hoodoo et pin |
| `canyon_hoodoos_02.jpg` | Hoodoos en grès ocre, lumière rasante | Proportions hoodoos, éclairage soir |
| `canyon_trail_pines_01.jpg` | Sentier rouge, champignons rocheux, conifères | Sentiers, rochers, sol rougeâtre |

Implémentation actuelle : `LandscapeManager` génère procéduralement un terrain 512 m (vallée de canyon + falaises périphériques) avec un shader de strates sédimentaires, et place par MultiMesh des hoodoos, buttes/mesas, rochers, pins, buissons et herbes — tous générés en code (`RockGenerator`, `VegetationGenerator`), sans asset externe, pour rester léger sur Android.

## 8. Pile technique (Godot 4)

- **Langage** : GDScript (rapidité de prototypage, lisible) — GDExtension C# possible plus tard si besoin de perfs.
- **Rendu** : Forward+ (PC) / Mobile (Android) avec dégradation automatique des réglages graphiques.
- **Monde ouvert** : scènes de région découpées + streaming de chunks autour du joueur (système de grille de chunks).
- **Génération procédurale** : placement de props, rochers, végétation, points d'eau ; squelette de POI authored par région.
- **Sauvegarde** : JSON/Resource par profil (position, équipement, journal, réputation, carte découverte).
- **Localisation** : français et anglais dès le départ (fichiers `.csv` de traduction Godot).
- **Exports** : Windows, macOS, Linux, Android (APK/AAB). itch.io + Google Play.

## 9. Roadmap

| Phase | Contenu | Durée indicative |
|---|---|---|
| **0 — Fondation** | Projet Godot 4, personnage qui marche/court, cycle jour/nuit, une plaine de test | 2–3 semaines |
| **1 — Boucle survie** | Soif/faim/température, feu de camp, chasse basique, inventaire et poids | 1–2 mois |
| **2 — Orientation** | Carte du monde, boussole, repères joueur, journal, se perdre | 1 mois |
| **3 — Région 1 jouable** | Ouest américain complet : faune, PNJ de base, 3–4 quêtes, progression réputation | 2–3 mois |
| **4 — Mobile** | Contrôles tactiles, UI adaptée, optimisation Android, export APK | 1 mois |
| **5 — Régions 2 & 3** | Australie + Canada | 2–3 mois |
| **6 — Polish & sortie** | Son, musique, équilibrage, localisation, itch.io + Play Store | 1–2 mois |

## 10. Risques et réponses

- **Scope du monde ouvert** → contenu procédural + squelette authored, une région à la fois, vertical slice d'abord.
- **Perfs Android** → low-poly, LOD, occlusion culling, test sur appareil milieu de gamme dès la phase 4.
- **Se perdre = frustration** → la boussole et la carte joueur sont toujours disponibles ; le « vrai » hardcore (boussole cassable) est une option de difficulté.
- **Représentation des peuples autochtones** → recherche documentaire, consultation, PNJ écrits comme individus, jamais comme stéréotypes.

---

*Document vivant — à faire évoluer au fil du développement.*
