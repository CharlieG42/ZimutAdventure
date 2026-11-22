class_name CharacterProfile
extends RefCounted
## Apparence du personnage : genre, teint, coiffure, couleurs. Sauvegardée dans
## user://character.cfg ; `exists()` est faux tant que le joueur n'a pas validé sa création.

const SAVE_NAME := "character.cfg"
const GENDERS := ["male", "female"]
const SKIN_TONES: Array[Color] = [
	Color(0.98, 0.84, 0.72), Color(0.92, 0.72, 0.56), Color(0.78, 0.55, 0.38),
	Color(0.58, 0.38, 0.25), Color(0.36, 0.23, 0.16),
]
const HAIR_STYLES := ["short", "long", "ponytail", "bun", "bald", "curly", "braid"]
const BEARDS := ["none", "stubble", "short", "full"]
const EYE_COLORS: Array[Color] = [
	Color(0.2, 0.13, 0.08), Color(0.25, 0.45, 0.7), Color(0.28, 0.55, 0.32), Color(0.45, 0.4, 0.3), Color(0.5, 0.55, 0.6),
]
const HAIR_COLORS: Array[Color] = [
	Color(0.12, 0.08, 0.06), Color(0.32, 0.2, 0.1), Color(0.62, 0.4, 0.18),
	Color(0.88, 0.7, 0.35), Color(0.55, 0.16, 0.1), Color(0.78, 0.78, 0.8),
]
const TUNIC_COLORS: Array[Color] = [
	Color(0.2, 0.42, 0.58), Color(0.66, 0.26, 0.2), Color(0.3, 0.5, 0.28),
	Color(0.86, 0.66, 0.2), Color(0.45, 0.3, 0.55), Color(0.82, 0.8, 0.74),
]
const PANTS_COLORS: Array[Color] = [
	Color(0.48, 0.36, 0.22), Color(0.26, 0.3, 0.4), Color(0.55, 0.5, 0.36), Color(0.2, 0.2, 0.2),
]

const NAME_MAX := 16

var hero_name: String = ""
var gender: String = "male"
var skin: int = 1
var hair_style: int = 0
var hair_color: int = 1
var tunic: int = 0
var pants: int = 0
var beard: int = 0
var eyes: int = 0

static func default_for(new_gender: String) -> CharacterProfile:
	var p := CharacterProfile.new()
	p.gender = new_gender
	p.hair_style = 0 if new_gender == "male" else 1
	p.tunic = 0 if new_gender == "male" else 1
	return p

## Nom sans espaces superflus ni retours à la ligne, limité à NAME_MAX caractères.
static func clean_name(raw: String) -> String:
	var cleaned := raw.replace("\n", " ").replace("\t", " ").strip_edges()
	return cleaned.substr(0, NAME_MAX).strip_edges()

## Nom affiché ; « Aventurier » tant que le joueur n'en a pas choisi.
func display_name() -> String:
	return hero_name if hero_name != "" else tr("CHAR_DEFAULT_NAME")

func skin_color() -> Color:
	return SKIN_TONES[clampi(skin, 0, SKIN_TONES.size() - 1)]

func hair_color_value() -> Color:
	return HAIR_COLORS[clampi(hair_color, 0, HAIR_COLORS.size() - 1)]

func tunic_color() -> Color:
	return TUNIC_COLORS[clampi(tunic, 0, TUNIC_COLORS.size() - 1)]

func pants_color() -> Color:
	return PANTS_COLORS[clampi(pants, 0, PANTS_COLORS.size() - 1)]

func eye_color() -> Color:
	return EYE_COLORS[clampi(eyes, 0, EYE_COLORS.size() - 1)]

func beard_name() -> String:
	return BEARDS[clampi(beard, 0, BEARDS.size() - 1)]

func hair_style_name() -> String:
	return HAIR_STYLES[clampi(hair_style, 0, HAIR_STYLES.size() - 1)]

func to_dict() -> Dictionary:
	return {"hero_name": hero_name, "gender": gender, "skin": skin, "hair_style": hair_style, "hair_color": hair_color,
			"tunic": tunic, "pants": pants, "beard": beard, "eyes": eyes}

static func from_dict(data: Dictionary) -> CharacterProfile:
	var p := CharacterProfile.new()
	p.hero_name = clean_name(String(data.get("hero_name", "")))
	p.gender = String(data.get("gender", "male"))
	if not GENDERS.has(p.gender):
		p.gender = "male"
	p.skin = clampi(int(data.get("skin", 1)), 0, SKIN_TONES.size() - 1)
	p.hair_style = clampi(int(data.get("hair_style", 0)), 0, HAIR_STYLES.size() - 1)
	p.hair_color = clampi(int(data.get("hair_color", 1)), 0, HAIR_COLORS.size() - 1)
	p.tunic = clampi(int(data.get("tunic", 0)), 0, TUNIC_COLORS.size() - 1)
	p.pants = clampi(int(data.get("pants", 0)), 0, PANTS_COLORS.size() - 1)
	p.beard = clampi(int(data.get("beard", 0)), 0, BEARDS.size() - 1)
	p.eyes = clampi(int(data.get("eyes", 0)), 0, EYE_COLORS.size() - 1)
	if p.gender == "female":
		p.beard = 0
	return p

static func exists() -> bool:
	return FileAccess.file_exists(SaveSlots.file(SAVE_NAME))

## Profil sauvegardé, ou un profil par défaut (homme) si le joueur n'en a pas encore créé.
static func load_saved() -> CharacterProfile:
	var config := ConfigFile.new()
	if config.load(SaveSlots.file(SAVE_NAME)) != OK:
		return CharacterProfile.default_for("male")
	return from_dict(config.get_value("character", "profile", {}))

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("character", "profile", to_dict())
	config.save(SaveSlots.file(SAVE_NAME))

## Pour les tests : efface la sauvegarde.
static func clear_saved() -> void:
	if FileAccess.file_exists(SaveSlots.file(SAVE_NAME)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSlots.file(SAVE_NAME)))
