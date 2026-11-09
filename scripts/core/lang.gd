class_name Lang
extends RefCounted
## Languages, like the classic game's language files. The game's texts are
## written in English; a language file maps each English text to its
## translation, one per line:
##   assets/lang/ru_ru.lang:   Video Settings...=Настройки графики...
## Lines starting with # are comments. Texts with %s / %d keep them.
##
## Translations go through Godot's TranslationServer, so labels and buttons
## translate themselves; texts built in code use Lang.t(). English is the
## default; adding a language = a new .lang file + a line in LANGUAGES.

const DIR := "res://assets/lang"
## [code, name shown in the Language screen]
const LANGUAGES := [
	["en_us", "English (US)"],
	["ru_ru", "Русский (Россия)"],
]

static var _loaded := {} # code -> Translation


## Translation of an English text in the current language.
static func t(text: String) -> String:
	return TranslationServer.translate(text)


## Switches the language (index into LANGUAGES).
static func apply(index: int) -> void:
	var code: String = LANGUAGES[clampi(index, 0, LANGUAGES.size() - 1)][0]
	if not _loaded.has(code):
		_loaded[code] = _load(code)
		TranslationServer.add_translation(_loaded[code])
	TranslationServer.set_locale(_locale(code))


static func _locale(code: String) -> String:
	return code.split("_")[0]


static func _load(code: String) -> Translation:
	var translation := Translation.new()
	translation.locale = _locale(code)
	var file := FileAccess.open(DIR.path_join(code + ".lang"), FileAccess.READ)
	if file == null:
		return translation
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var split := line.find("=")
		if split <= 0:
			continue
		translation.add_message(line.substr(0, split), line.substr(split + 1).replace("\\n", "\n"))
	return translation
