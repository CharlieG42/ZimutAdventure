# Animaux animés

Modèles 3D animés des animaux, de **Quaternius** — licence **CC0 1.0** (domaine public,
attribution non obligatoire mais donnée ici par courtoisie) : https://quaternius.com

| Fichier | Espèce dans le jeu | Pack d'origine |
|---|---|---|
| `deer.glb`, `stag.glb` | cerf (biche ou cerf à bois, au hasard) | Ultimate Animated Animal Pack |
| `wolf.glb` | loup | Ultimate Animated Animal Pack |
| `coyote.glb` | coyote (le renard du pack, repeint en jeu) | Ultimate Animated Animal Pack |
| `cow.glb` | vache | Ultimate Animated Animal Pack |
| `horse.glb` | cheval | Ultimate Animated Animal Pack |
| `shiba_inu.glb` | chien | Ultimate Animated Animal Pack |
| `sheep.glb` | mouton | Farm Animal Pack (2018) |

Le lièvre, la chèvre et la poule gardent leur modèle construit en code : il n'existe pas de
modèle CC0 animé de ces animaux dans le même style.

## Conversion

Les fichiers d'origine (.gltf à tampon embarqué, ~3 Mo chacun) ont été convertis en .glb avec
`tools/gltf2glb.py`, qui ne garde que les animations utilisées (repos, broutage, marche,
galop, attaque, chute) et retire les images clés redondantes (interpolation linéaire, écart
invisible). Exemple :

```sh
python3 tools/gltf2glb.py Deer.gltf assets/animals/deer.glb \
    Idle,Idle_2,Idle_Headlow,Eating,Walk,Gallop,Death,Attack_Headbutt
```

Les modèles sont choisis, mis à l'échelle et animés par `scripts/world/animal_rig.gd`.
