extends Node
## Portées d'affichage du décor interactif et des animaux : au-delà, le moteur ne les dessine
## plus (ils continuent de vivre). Les nœuds apparus en cours de partie sont pris en compte
## à chaque passage.

## Nom du nœud frère -> portée en mètres.
const RANGES := {
	"Livestock": 140.0,
	"Animals": 150.0,
	"Predators": 170.0,
	"BerryBushes": 110.0,
	"ChoppableTrees": 230.0,
	"BreakableRocks": 160.0,
	"Collectibles": 90.0,
	"WoodCollectibles": 90.0,
	"Fishing": 170.0,
	"Sites": 280.0,
	"Structures": 220.0,
}
const SCAN_SECONDS := 2.0
const MARK := "culled_range"

var _timer: float = 0.0

func _ready() -> void:
	apply.call_deferred()

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= SCAN_SECONDS:
		_timer = 0.0
		apply()

## Applique les portées aux maillages pas encore traités. Retourne le nombre traité.
func apply() -> int:
	var parent := get_parent()
	if parent == null:
		return 0
	var done := 0
	for node_name in RANGES:
		var group := parent.get_node_or_null(node_name)
		if group == null:
			continue
		for child in group.find_children("*", "GeometryInstance3D", true, false):
			var geometry := child as GeometryInstance3D
			if geometry.has_meta(MARK):
				continue
			geometry.set_meta(MARK, true)
			geometry.visibility_range_end = float(RANGES[node_name])
			geometry.visibility_range_end_margin = 8.0
			done += 1
	return done
