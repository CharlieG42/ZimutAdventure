extends Node
## Annonce le nom de la zone quand le joueur y entre (pinède, mesas, rivière, plaine).
## La zone doit rester la même pendant deux relevés : pas d'annonces en rafale sur une lisière.

signal zone_entered(zone: String)

const CHECK_SECONDS := 1.0

var current_zone: String = ""
var _candidate: String = ""
var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_SECONDS:
		return
	_timer = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var landscape := get_tree().get_first_node_in_group("landscape") as Node3D
	if player == null or landscape == null or not landscape.has_method("zone_at"):
		return
	observe(String(landscape.call("zone_at", player.global_position.x, player.global_position.z)), landscape)

## Prend en compte un relevé de zone. Retourne true si une nouvelle zone est annoncée.
func observe(zone: String, landscape: Node) -> bool:
	if zone == current_zone:
		_candidate = ""
		return false
	if zone != _candidate:
		_candidate = zone
		return false
	var first := current_zone.is_empty()
	current_zone = zone
	_candidate = ""
	zone_entered.emit(zone)
	# La zone de départ ne s'annonce pas : le joueur vient d'arriver.
	if first:
		return false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", tr(String(landscape.call("zone_name_key", zone))), 2.6)
	return true
