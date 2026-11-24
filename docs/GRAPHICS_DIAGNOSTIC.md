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

### P0 — rapides, gros gain (quelques heures) — **implémenté**

1. **MSAA 2x** : `rendering/anti_aliasing/quality/msaa_3d=1` dans `project.godot` ;
   `PerformanceGuard` le coupe au niveau 2 (`viewport.msaa_3d`, réglage runtime).
2. **SSAO coupé au niveau 1, glow au niveau 2** via le `WorldEnvironment`
   (`_apply_env_quality`), restaurés au niveau 0.
3. **Palier intermédiaire** : `scaling_3d_scale` 1.0 → 0.9 (niveau 1) → 0.8 (niveau 2).

### P1 — fort impact visuel, coût moyen (1-3 jours)

4. **Ciel en shader custom** ✅ **FAIT** (`assets/vfx/sky/sky.gdshader`, remplace le
   `ProceduralSkyMaterial` dans `canyon_playground.tscn`) : étoiles procédurales
   la nuit (hash 3D + scintillement), **lune visible** (disque + halo) qui suit la
   `moon` light, nuages en drift (défilement UV de `cloud_cover.png`, masque alpha),
   gradient de crépuscule plus riche, disque solaire + halo. Piloté par
   `DayNightCycle` via les uniforms (heure, météo, saison). Note Godot 4.7 : dans un
   `shader_type sky`, le point d'entrée est `void sky()` (pas `fragment()`), `EYEDIR`
   n'existe que dans les fonctions d'entrée (pas dans les helpers) et `COLOR` est un
   `vec3`.
5. **Eau améliorée** ✅ **FAIT** : Fresnel teinté par la couleur du ciel à l’horizon +
   reflet du soleil (glint : lobe serré dans la direction miroir des vaguelettes, amplifié
   dans l’émission pour le bloom → traînée de soleil) dans `water_surface.gdshader` et
   `river_surface.gdshader`. `DayNightCycle` publie les paramètres globaux `sun_dir`,
   `sun_tint`, `sun_amount`, `sky_reflect`. Pas de réflexion réelle possible en
   Compatibility (pas de probes) — le Fresnel simule bien.
6. **Feu de camp la nuit** ✅ **FAIT** : halo billboard additif (`flare_01.png`,
   émission ×4 capté par le bloom) pulsé et renforcé la nuit, flicker de la teinte
   de la lumière vers le rouge, braises montantes existantes (`SparkVfx`). Point focal
   nocturne du camp.

### P2 — polish (quelques jours)

7. **Rim light** ✅ **FAIT** dans `prop_atmosphere.gdshaderinc` (`rim_light()` : fresnel du
   contour teinté `sun_tint`, modulé par la face éclairée et `sun_amount`), inclus et appliqué
   dans `prop_rock.gdshader` et `prop_trunk.gdshader` : les rochers/troncs « pop » au contre-jour.
8. **Translucidité des feuilles** ✅ **FAIT** : backlight simple dans `prop_foliage.gdshader`
   (`pow(dot(view, -sun_dir), 2)` teinté `sun_tint` × `sun_amount`, désactivé sous la neige) —
   pas de vrai SSS en Compatibility.
9. **Variations de teinte par instance** ✅ **FAIT** sur les MultiMesh : `use_colors` +
   `set_instance_color` (hash déterministe de la position monde) dans
   `landscape_manager._place_multimesh`, lu via `COLOR` (varying `v_inst`) dans
   `prop_rock`/`prop_trunk`/`prop_foliage`. Note Godot 4.7 : `use_colors` doit être
   activé AVANT `instance_count`, et les couleurs vivent dans le RenderingServer
   (illisibles en headless dummy).
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

Commencer par **P0 (MSAA + coupe SSAO/glow en low)** ✅ **FAIT** — puis **P1-4 (ciel
custom nuit/lune/étoiles)** ✅ **FAIT** qui est le plus visible en screenshots.
**P1-5 (eau : Fresnel ciel + reflet de soleil)** ✅ **FAIT**. **P1-6 (feu de camp : halo bloom + flicker)** ✅ **FAIT**. **P2 (rim light, backlight, teintes par instance)** ✅ **FAIT**. Reste : P2-10 (SSAO renforcé en high) et P3.
