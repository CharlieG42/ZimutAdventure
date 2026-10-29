class_name PlatformInfo
extends RefCounted
## Détection de plateforme centralisée (évite de dupliquer
## `DisplayServer.get_name() == "android"` dans chaque script).
##
## Pour prévisualiser ou tester l'interface tactile sur PC :
##   ZIMUT_FORCE_TOUCH=1  -> force le mode tactile
##   ZIMUT_FORCE_TOUCH=0  -> force le mode clavier/souris

const ENV_FORCE_TOUCH := "ZIMUT_FORCE_TOUCH"

static func is_touch() -> bool:
	var forced := OS.get_environment(ENV_FORCE_TOUCH)
	if forced == "1":
		return true
	if forced == "0":
		return false
	return OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.get_name() == "android"
