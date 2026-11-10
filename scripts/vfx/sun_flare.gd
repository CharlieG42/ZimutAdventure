class_name SunFlare
extends Sprite3D
## Flare solaire : halo additif (texture Kenney flare_01) placé loin dans la direction
## du soleil, visible seulement quand le soleil est dans l'axe de la caméra.
## Il rougit quand le soleil est bas (aube / crépuscule).

const DOT_MIN := 0.985
const FLARE_DISTANCE := 600.0

func _ready() -> void:
	texture = VfxParticles.tex("flare_01")
	shaded = false
	double_sided = false
	pixel_size = 0.35
	modulate = Color(1.0, 0.9, 0.7, 0.8)
	visible = false
	add_to_group("sun_flare")

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D if get_tree() != null else null
	if cam == null or sun == null:
		visible = false
		return
	# Direction vers le soleil : les rayons de la DirectionalLight partent en -Z.
	var sun_dir := sun.global_transform.basis.z
	var cam_fwd := -cam.global_transform.basis.z
	visible = flare_visible(cam_fwd, sun_dir, sun.visible)
	if visible:
		global_position = cam.global_position + sun_dir * FLARE_DISTANCE
		var low := clampf(1.0 - sun_dir.y * 3.0, 0.0, 1.0)
		modulate = Color(1.0, 0.9 - 0.5 * low, 0.75 - 0.45 * low, 0.85)

## Visibilité du flare : soleil levé et dans le cône étroit de la caméra.
static func flare_visible(cam_fwd: Vector3, sun_dir: Vector3, sun_on: bool) -> bool:
	return sun_on and sun_dir.y > -0.02 and cam_fwd.dot(sun_dir) > DOT_MIN
