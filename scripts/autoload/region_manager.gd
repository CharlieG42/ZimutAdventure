extends Node
## Gestionnaire des régions (biomes) : définition des cartes, déblocage par niveau du joueur,
## persistance par emplacement de sauvegarde, et voyage entre les cartes.
## Chaque région = une scène monde + une palette (ciel/terrain/météo) + une faune,
## appliquées à l'exécution par world_setup / day_night_cycle / weather_manager.

signal region_changed(region_id: String)

const SAVE_NAME := "region.cfg"
const DEFAULT_REGION := "western"

## Palettes de l'Ouest américain = valeurs historiques (aucun changement visuel).
const REGIONS := {
	"western": {
		"name_key": "REGION_AMERICAN_WEST",
		"desc_key": "REGION_AMERICAN_WEST_DESC",
		"scene": "res://scenes/world/canyon_playground.tscn",
		"unlock_level": 1,
		"palette": {
			"top_day": Color(0.20, 0.45, 0.86), "top_night": Color(0.09, 0.09, 0.27),
			"horizon_day_a": Color(0.98, 0.80, 0.58), "horizon_day_b": Color(1.0, 0.5, 0.24),
			"horizon_night": Color(0.20, 0.12, 0.30),
			"ground_day": Color(0.35, 0.22, 0.14), "ground_night": Color(0.02, 0.02, 0.05),
			"ambient_night": Color(0.36, 0.46, 0.80),
			"fog_day_a": Color(0.86, 0.66, 0.5), "fog_day_b": Color(1.0, 0.5, 0.3),
			"fog_night": Color(0.12, 0.10, 0.26),
		},
		"terrain": {},
		"weather": {},
		"animals": {"passive": ["deer", "rabbit"], "predators": ["coyote", "wolf"]},
		"aurora": 0.0,
	},
	"outback": {
		"name_key": "REGION_AUSTRALIAN_OUTBACK",
		"desc_key": "REGION_AUSTRALIAN_OUTBACK_DESC",
		"scene": "res://scenes/world/outback_playground.tscn",
		"unlock_level": 4,
		"palette": {
			"top_day": Color(0.30, 0.50, 0.85), "top_night": Color(0.10, 0.06, 0.24),
			"horizon_day_a": Color(1.0, 0.66, 0.38), "horizon_day_b": Color(1.0, 0.38, 0.12),
			"horizon_night": Color(0.24, 0.10, 0.26),
			"ground_day": Color(0.55, 0.30, 0.16), "ground_night": Color(0.03, 0.02, 0.04),
			"ambient_night": Color(0.40, 0.34, 0.70),
			"fog_day_a": Color(0.95, 0.62, 0.38), "fog_day_b": Color(1.0, 0.42, 0.18),
			"fog_night": Color(0.14, 0.07, 0.22),
		},
		"terrain": {
			"strata_light": Color(0.88, 0.42, 0.18), "strata_mid": Color(0.70, 0.28, 0.12),
			"strata_dark": Color(0.50, 0.22, 0.10), "strata_accent": Color(0.92, 0.58, 0.26),
			"ground_dust": Color(0.82, 0.52, 0.30), "ground_red": Color(0.72, 0.36, 0.15),
			"badlands_red": Color(0.74, 0.30, 0.12), "bank_grass_dry": Color(0.66, 0.58, 0.26),
		},
		"weather": {"season": "summer"},
		"animals": {"passive": ["kangaroo", "rabbit"], "predators": ["dingo"]},
		"aurora": 0.0,
	},
	"canada": {
		"name_key": "REGION_CANADIAN_NORTH",
		"desc_key": "REGION_CANADIAN_NORTH_DESC",
		"scene": "res://scenes/world/canada_playground.tscn",
		"unlock_level": 8,
		"palette": {
			"top_day": Color(0.15, 0.30, 0.60), "top_night": Color(0.03, 0.05, 0.12),
			"horizon_day_a": Color(0.75, 0.80, 0.90), "horizon_day_b": Color(0.95, 0.75, 0.70),
			"horizon_night": Color(0.08, 0.10, 0.20),
			"ground_day": Color(0.55, 0.57, 0.62), "ground_night": Color(0.02, 0.03, 0.06),
			"ambient_night": Color(0.20, 0.30, 0.55),
			"fog_day_a": Color(0.72, 0.78, 0.86), "fog_day_b": Color(0.85, 0.80, 0.82),
			"fog_night": Color(0.05, 0.07, 0.14),
		},
		"terrain": {
			"strata_light": Color(0.75, 0.76, 0.80), "strata_mid": Color(0.60, 0.62, 0.67),
			"strata_dark": Color(0.45, 0.47, 0.53), "strata_accent": Color(0.82, 0.84, 0.88),
			"ground_dust": Color(0.80, 0.82, 0.87), "ground_pale": Color(0.86, 0.88, 0.92),
			"ground_red": Color(0.55, 0.45, 0.42), "pebble_dark": Color(0.40, 0.42, 0.47),
			"bank_grass": Color(0.33, 0.42, 0.30), "forest_floor": Color(0.30, 0.31, 0.34),
			"badlands_red": Color(0.55, 0.52, 0.55),
		},
		"weather": {"season": "winter"},
		"animals": {"passive": ["moose", "deer"], "predators": ["wolf", "bear"]},
		"aurora": 1.0,
	},
}

var current_region: String = DEFAULT_REGION
## Pour les tests : ne change pas de scène.
var change_scene_enabled: bool = true

var _autosave: bool = true

func _ready() -> void:
	_load()

func region_ids() -> Array:
	return REGIONS.keys()

func has_region(region_id: String) -> bool:
	return REGIONS.has(region_id)

func def(region_id: String) -> Dictionary:
	return REGIONS.get(region_id, REGIONS[DEFAULT_REGION])

func scene_for(region_id: String) -> String:
	return String(def(region_id).get("scene", REGIONS[DEFAULT_REGION]["scene"]))

func unlock_level(region_id: String) -> int:
	return int(def(region_id).get("unlock_level", 1))

func is_unlocked(region_id: String) -> bool:
	var progression := InteractionManager.get_progression()
	var level := int(progression.call("get_level")) if progression != null else 1
	return level >= unlock_level(region_id)

func palette(region_id: String = "") -> Dictionary:
	return def(region_id if region_id != "" else current_region).get("palette", {})

func animals(kind: String, region_id: String = "") -> Array:
	var a: Dictionary = def(region_id if region_id != "" else current_region).get("animals", {})
	return a.get(kind, [])

## Voyage vers une autre région (si débloquée) : mémorise, sauvegarde, charge la scène.
func travel_to(region_id: String) -> bool:
	if not has_region(region_id) or not is_unlocked(region_id):
		return false
	if region_id == current_region:
		return true
	current_region = region_id
	region_changed.emit(region_id)
	_save()
	if change_scene_enabled and is_inside_tree():
		get_tree().change_scene_to_file(scene_for(region_id))
	return true

## Applique la région courante au monde chargé (appelé par world_setup).
func apply_to_world(root: Node) -> void:
	var d := def(current_region)
	# Météo / saison / neige de la région.
	var weather := get_node_or_null("/root/Weather")
	if weather != null and weather.has_method("apply_region_weather"):
		weather.call("apply_region_weather", d.get("weather", {}))
	# Teintes du terrain de la région.
	var landscape := root.get_node_or_null("Landscape")
	if landscape != null and landscape.has_method("apply_region_palette"):
		landscape.call("apply_region_palette", d.get("terrain", {}))
	# Annonce d'entrée dans la région.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", tr("REGION_ENTER") % tr(String(d.get("name_key", ""))), 4.0)

# --- Sauvegarde (par emplacement de partie) ---------------------------------------------------

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SaveSlots.file(SAVE_NAME)) != OK:
		current_region = DEFAULT_REGION
		return
	current_region = String(config.get_value("region", "current", DEFAULT_REGION))
	if not has_region(current_region):
		current_region = DEFAULT_REGION

func reload_from_disk() -> void:
	_load()

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("region", "current", current_region)
	config.save(SaveSlots.file(SAVE_NAME))

## API de test : repart de la région de départ, sans écrire sur le disque.
func clear_for_test() -> void:
	_autosave = false
	current_region = DEFAULT_REGION
