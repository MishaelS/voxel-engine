class_name LanguageScreen
extends MenuScreen
## "Language", like the classic game: the languages (Lang.all()), the
## current one marked; click to switch at once.

var _buttons: Array[Button] = []


func _init() -> void:
	title = "Language"
	columns = 1


func build() -> void:
	for i in Lang.all().size():
		var button := add_list_wide_button("", func() -> void:
			Settings.set_value("language", i)
			# Rebuild in the new language.
			menu.back()
			menu.push(LanguageScreen.new()))
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_buttons.append(button)
	add_done_button()
	_update()


func _update() -> void:
	var current: int = Settings.get_value("language")
	for i in _buttons.size():
		var language_name: String = Lang.all()[i][1]
		_buttons[i].text = ("> %s <" % language_name) if i == current else language_name
