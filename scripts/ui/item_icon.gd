class_name ItemIcon
extends TextureRect
## Icône d'item/outil du HUD : texture PNG générée (assets/ui/icons/items/),
## repli sur le glyphe dessiné en code (ToolIcon) pour les outils.

const ICON_ROOT := "res://assets/ui/icons/items/"

static var _cache: Dictionary = {}

var item_id: String = ""

func set_item(id: String) -> void:
	item_id = id
	_refresh()

func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()

func _refresh() -> void:
	if item_id.is_empty():
		texture = null
		return
	if _cache.has(item_id):
		texture = _cache[item_id]
		return
	var t: Texture2D = load(ICON_ROOT + item_id + ".png")
	_cache[item_id] = t
	texture = t
