class_name OptionsScreen
extends MenuScreen
## Options: general settings and links to the setting groups.


func _init() -> void:
	title = "Options"


func build() -> void:
	for setting: Setting in Settings.in_category("general"):
		add_option(setting)
	add_list_button("Video Settings...", func() -> void:
		menu.push(SettingsListScreen.new("Video Settings", "video")))
	add_list_button("Controls...", func() -> void: menu.push(ControlsScreen.new()))
	add_list_button("World Settings...", func() -> void: menu.push(WorldSettingsScreen.new()))
	add_done_button()
