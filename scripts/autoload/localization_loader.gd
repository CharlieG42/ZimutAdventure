extends Node

const TRANSLATION_FILES := {
	"fr": "res://locales/translations.fr.fr.translation",
	"en": "res://locales/translations.en.en.translation",
}

func _ready() -> void:
	for locale in TRANSLATION_FILES:
		var path: String = TRANSLATION_FILES[locale]
		if not ResourceLoader.exists(path):
			push_warning("LocalizationLoader: missing compiled translation %s" % path)
			continue
		var translation: Translation = load(path)
		if translation:
			TranslationServer.add_translation(translation)

	var saved_locale := _read_saved_locale()
	if saved_locale in TRANSLATION_FILES:
		TranslationServer.set_locale(saved_locale)
	else:
		var system_locale := TranslationServer.get_locale()
		var short := system_locale.substr(0, 2)
		TranslationServer.set_locale(short if short in TRANSLATION_FILES else "en")

func set_game_locale(locale: String) -> void:
	if locale in TRANSLATION_FILES:
		TranslationServer.set_locale(locale)
		_save_locale(locale)

func _read_saved_locale() -> String:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		return config.get_value("display", "locale", "")
	return ""

func _save_locale(locale: String) -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("display", "locale", locale)
	config.save("user://settings.cfg")
