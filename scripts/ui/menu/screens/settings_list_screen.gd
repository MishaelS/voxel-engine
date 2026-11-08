class_name SettingsListScreen
extends MenuScreen
## Every setting of one Settings category, e.g. "video". A new setting in
## that category appears here without touching the menu code.

var _category := ""


func _init(screen_title: String, category: String) -> void:
	title = screen_title
	_category = category


func build() -> void:
	for setting: Setting in Settings.in_category(_category):
		add_option(setting)
	add_bottom_button("Reset to Defaults", func() -> void:
		Settings.reset_category(_category)
		refresh())
	add_done_button()
