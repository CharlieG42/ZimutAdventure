# Zimut — personnages modulaires V5

La V5 conserve la direction artistique et le squelette commun Mixamo de la V4. Elle corrige surtout la gestion des parties de peau sous les vêtements.

## Fichiers
- `male_modular_v5.glb` et `female_modular_v5.glb` : personnages habillés, sans peau cachée sous les vêtements.
- `male_nude_parts_v5.glb` et `female_nude_parts_v5.glb` : corps nus découpés en pièces indépendantes.
- `generate_prototype.py` : source de génération reproductible.

## Correction des intersections peau/vêtements
Dans les personnages habillés, seuls `Body_Head`, `Body_Neck` et `Body_Hands` sont conservés comme peau visible. Les parties de peau recouvertes par les vêtements (torse, bassin, bras, cuisses, jambes et pieds) sont absentes de ces deux fichiers : elles ne peuvent donc plus traverser la tunique, la robe, le pantalon ou les bottes lorsque les membres se plient.

## Corps nus modulaires
Les fichiers `*_nude_parts_v5.glb` contiennent les pièces suivantes : tête, cou, mains, avant-bras, bras supérieurs, torse, bassin, cuisses, jambes inférieures et pieds. Les noms sont `Body_Head`, `Body_Neck`, `Body_Hands`, `Body_Forearms`, `Body_UpperArms`, `Body_Torso`, `Body_Pelvis`, `Body_Thighs`, `Body_LowerLegs`, `Body_Feet`. Chaque pièce est un objet séparé et skinné sur le même squelette.

## Chevelure et cape
- La chevelure longue féminine reçoit deux mèches frontales plus épaisses qui passent devant les épaules et restent visibles de face.
- La cape reste indépendante (`Fur_Cape`) et dispose d'un col de fourrure visible de face ainsi que de pans latéraux visibles de profil (`Fur_Cape_Collar`, `Fur_Cape_Sides`).

## Rig et repères
- Hiérarchie commune de 22 os `mixamorig_…`.
- Y vers le haut, visage vers +Z, pieds proches de Y=0.
- Aucune animation factice incluse.

## Limites de validation
Les modèles sont générés en géométrie low-poly procédurale. La séparation des pièces et la suppression des surfaces de peau cachées sont vérifiées dans les GLB, mais il reste nécessaire de tester le skinning et les raccords dans Godot avec les animations réelles de marche/course et les poses de combat. Les fichiers nus sont une base modulaire, pas un système automatique d'équipement : les pièces doivent être assemblées et les objets inutilisés masqués dans le jeu.
