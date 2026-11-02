class_name AnimalInteraction
extends Interactable
## Zone d'interaction d'un animal domestique : transmet l'invite et l'action à l'animal.

var animal: Node

static func create(owner_animal: Node) -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/world/animal_interaction.gd"))
	area.set("animal", owner_animal)
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "Interaction"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	shape.shape = sphere
	shape.position = Vector3(0.0, 0.8, 0.0)
	area.add_child(shape)
	return area

func can_interact() -> bool:
	return enabled and animal != null and is_instance_valid(animal) and bool(animal.call("can_interact_now"))

func get_prompt() -> String:
	if animal != null and is_instance_valid(animal):
		return String(animal.call("get_prompt_key"))
	return prompt_text

## Transmet les arguments d'invite (nourriture requise pour apprivoiser, etc.).
func get_prompt_args() -> Array:
	if animal != null and is_instance_valid(animal) and animal.has_method("get_prompt_args"):
		return animal.call("get_prompt_args")
	return []

func _on_interact(interactor: Node3D) -> void:
	if animal != null and is_instance_valid(animal):
		animal.call("interact_with", interactor)
