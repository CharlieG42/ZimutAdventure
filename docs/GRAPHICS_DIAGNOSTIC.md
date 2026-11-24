# Diagnostic — améliorations graphiques possibles

État des lieux du rendu (Godot 4.7, rendu **GL Compatibility** — contrainte forte : pas de
Forward+, pas de SSR/reflection probes, pas de DOF bokeh, pas de compute shaders) et
propositions classées par coût/bénéfice. Références au code actuel entre parenthèses.

## État des lieux

- **Environnement** (`scenes/world/canyon_playground.tscn`) : ciel procédural +
  couverture nuageuse statique, lumière ambiante depuis le ciel, tonemap (exposure 0.9),
  **glow/bloom activé**, **SSAO activé** (radius 1.5), brouillard + perspective aérienne
  + brouillard de hauteur, `adjustment` (saturation 1.25, contraste 1.12).
- **Cycle jour/nuit** (`day_night_cycle.gd`) : soleil/lune (énergie, couleur, saison),
  couleurs de ciel, ambiance, brouillard pilotés par l'heure et la météo ; variables
  globales de shader `snow_amount` / `wetness` / `foliage_tint`.
- **Terrain** (`canyon_terrain.gdshader`) : strates sédimentaires, zones colorées, bruit,
  variation par facette, détail proche fondu avec la distance, neige/sol mouillé.
- **Props** : shaders dédiés roche/feuillage/tronc + include `prop_atmosphere` (vent,
  fondu de distance) ; props en MultiMesh + `distance_culler` + `mesh_baker`.
- **Eau** (`water_surface.gdshader`, `river_surface.gdshader`) : ondulations procédurales,
  reflets scintillants, bord clair, gel hiver.
- **VFX** : particules Kenney, overlays 2D (vignette, grain film, empreintes de pas),
  `sun_flare`, mesas d'horizon (`horizon_mesa.gdshader`).
- **Perfs** (`performance_guard.gd`) : qualité auto 3 niveaux (particules, ombres
  allégées, `scaling_3d_scale` 0.8), overlay FPS/draws (F3), log `user://perf.log`.
- **Non présent** : MSAA 3D (aucun réglage `msaa` dans `project.godot`), pas d'étoiles
  la nuit, pas de lune visible dans le ciel, nuages statiques, pas de rim light.

## Propositions, par priorité

### P0 — rapides, gros gain (quelques heures)

1. **MSAA 2x** : aucun `msaa_3d` n'est réglé → l'anti-aliasing est inactif. Activer
   `viewport.msaa_3d = Viewport.MSAA_2X` au démarrage, et le couper au niveau de
   qualité bas de `PerformanceGuard` (réglage runtime via le viewport). Nettement
   meilleur rendu des arêtes (rochers, personnages, HUD 3D) pour un coût modéré.
2. **Couper SSAO et glow en qualité basse** : `PerformanceGuard` level ≥ 2 ne touche
   aujourd'hui que particules/ombres/rendu. En Compatibility, SSAO et bloom sont des
   passes plein écran coûteuses : les désactiver via le `WorldEnvironment` en low
   (garder en high sur PC). Gros gain FPS sur mobile milieu de gamme.
3. **Niveau intermédiaire de rendu** : ajouter `scaling_3d_scale = 0.9` entre 1.0 et
   0.8 pour adoucir la dégradation auto.

### P1 — fort impact visuel, coût moyen (1-3 jours)

4. **Ciel en shader custom** (remplace `ProceduralSkyMaterial`) : étoiles procédurales
   la nuit (hash 3D + scintillement), **lune visible** (disque + halo) qui suit la
   `moon` light, nuages en drift (défilement UV de `cloud_cover.png`), gradient de
   crépuscule plus riche. Un seul `sky.gdshader`, piloté par les mêmes variables
   (heure, météo, saison). C'est le plus gros « wow » la nuit.
5. **Eau améliorée** : ajouter un Fresnel avec teinte de ciel reflété + reflet du soleil
   (specular directionnelle) dans `water_surface.gdshader`/`river_surface.gdshader` ;
   éventuellement transparence accrue près des berges. Pas de réflexion réelle
   possible en Compatibility (pas de probes) — le Fresnel simule bien.
6. **Feu de camp la nuit** : la lumière existe ; ajouter un halo émissif fort (capté
   par le bloom) + particules de braises montantes (`flame_*.png` existent) +
   éclairage orange pulsant. C'est le point focal nocturne du camp.

### P2 — polish (quelques jours)

7. **Rim light** léger dans `prop_atmosphere.gdshaderinc` (fresnel contre le soleil) :
   fait « pop » personnages et rochers au contre-jour, quasi gratuit.
8. **Translucidité des feuilles** au contre-jour (backlight simple dans
   `prop_foliage.gdshader`, pas de vrai SSS en Compatibility).
9. **Variations de teinte par instance** sur les MultiMesh (déjà partiellement là via
   les facettes) : hue shift léger par buisson/arbre pour casser la répétition.
10. **Ombres de contact du personnage** : le SSAO aide déjà ; en high, augmenter
    `ssao_radius`/`intensity` légèrement sur PC uniquement.

### P3 — plus lourd / régions futures

11. **Aurores boréales** (bandes animées dans le ciel custom) — pour la région Grand
    Nord canadien (GDD), pas pour le canyon.
12. **Comètes/étoiles filantes** la nuit (2-3 sprites animés dans le ciel).
13. **Lumière dynamique des lucioles la nuit** (quelques point lights éteintes par
    distance, ou émissif + pas d'ombre) — ambiance, à budgetiser.
14. **Reflets d'eau réels** : impossibles en Compatibility (pas de probes/SSR) — rester
    sur le Fresnel (P1-5).

## Contraintes à respecter

- Rester en **GL Compatibility** (cible Android) : pas de Forward+, SSR, probes,
  DOF bokeh, compute. Le MSAA 2x/4x, le glow, le SSAO et le fog existent et sont
  réglables à runtime.
- Tout effet doit passer par `PerformanceGuard` (niveau 0/1/2) et rester testable
  headless (`DisplayServer.get_name() == "headless"` guards existants).
- Textures générées par les scripts `tools/generate_*.py` (Pillow) si besoin.

## Recommandation

Commencer par **P0 (MSAA + coupe SSAO/glow en low)** — 1 PR courte, testable via
`test_quality_shadows`-style — puis **P1-4 (ciel custom nuit/lune/étoiles)** qui est
le plus visible en screenshots. P1-5 (eau) et P1-6 (feu de camp) suivent bien.
