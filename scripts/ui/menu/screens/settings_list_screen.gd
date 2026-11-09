class_name SettingsListScreen
extends MenuScreen
## Every setting of one Settings category, e.g. "video". A new setting in
## that category appears here without touching the menu code.

var _category := ""


func _init(screen_title: String, category: String) -> void:
	title = screen_title
	_category = category


func build() -> void:
	var all_toggles := true
	for setting: Setting in Settings.in_category(_category):
		add_option(setting)
		all_toggles = all_toggles and setting.kind == Setting.Kind.BOOL
	if all_toggles:
		# Like the classic Animations screen: everything on / off at once.
		add_bottom_row([
			["All ON", func() -> void: _set_all(true)],
			["All OFF", func() -> void: _set_all(false)],
		])
	add_bottom_button("Reset to Defaults", func() -> void:
		Settings.reset_category(_category)
		refresh())
	add_done_button()


func _set_all(value: bool) -> void:
	for setting: Setting in Settings.in_category(_category):
		setting.set_value(value)
	refresh()
