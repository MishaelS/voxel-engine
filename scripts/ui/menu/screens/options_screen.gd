class_name OptionsScreen
extends MenuScreen
## "Options", laid out like the modern classic game: FOV on top, then the
## sections: Video Settings, Controls, Language, Texture Packs and (in a
## world) World Settings. The isometric camera's settings are in its own
## view (F6, IsometricPanel).


func _init() -> void:
	title = "Options"


func build() -> void:
	for setting: Setting in Settings.in_category("general"):
		add_option(setting)
	if menu.world:
		add_list_button("World Settings...", func() -> void: menu.push(WorldSettingsScreen.new()))
	else:
		add_list_item(Control.new())
	# A gap row, like the classic screen.
	add_list_item(Control.new())
	add_list_item(Control.new())
	add_list_button("Video Settings...", func() -> void: menu.push(VideoSettingsScreen.new()))
	add_list_button("Controls...", func() -> void: menu.push(ControlsScreen.new()))
	add_list_button("Language...", func() -> void: menu.push(LanguageScreen.new()))
	add_list_button("Texture Packs...", func() -> void: menu.push(TexturePacksScreen.new()))
	add_done_button()
