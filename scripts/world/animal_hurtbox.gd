class_name AnimalHurtbox
extends Area3D
## Boîte de touche généreuse autour du gibier (couche 8) : une flèche qui passe
## à proximité compte quand même. Transfère le hit au parent (take_arrow_hit).
## La flèche (scripts/interaction/arrow.gd) teste take_arrow_hit sur tout ce qu'elle
## touche : comme cette zone l'expose, elle suffit à enregistrer l'impact.

func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = true

## Appelée par la flèche quand elle touche cette zone.
func take_arrow_hit(from_position: Vector3) -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("take_arrow_hit"):
		parent.call("take_arrow_hit", from_position)
