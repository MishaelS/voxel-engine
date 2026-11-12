class_name OptionsScreen
extends MenuScreen
## "Options", laid out like the modern classic game in two even columns:
## volumes, FOV and difficulty on top, then the sections in pairs: Video
## Settings and Controls, Language and Texture Packs, and (in a world)
## World Settings and Shaders. The isometric camera's settings are in its own
## view (F6, IsometricPanel).


func _init() -> void:
	title = "Options"


func build() -> void:
	# Two columns, every row full: the options, a gap row, then the sections
	# in pairs (in a world, World Settings pairs with Shaders).
	var options: Array = Settings.in_category("general")
	for setting: Setting in options:
		add_option(setting)
	if options.size() % 2 == 1:
		add_list_item(Control.new())
	for i in 2: # a gap row, like the classic screen
		var gap := Control.new()
		gap.custom_minimum_size.y = 6 * UiTheme.PIXEL
		add_list_item(gap)
	add_list_button("Video Settings...", func() -> void: menu.push(VideoSettingsScreen.new()))
	add_list_button("Controls...", func() -> void: menu.push(ControlsScreen.new()))
	add_list_button("Language...", func() -> void: menu.push(LanguageScreen.new()))
	add_list_button("Texture Packs...", func() -> void: menu.push(TexturePacksScreen.new()))
	add_list_button("Player Settings...", func() -> void: menu.push(PlayerSettingsScreen.new()))
	if menu.world:
		add_list_button("World Settings...", func() -> void: menu.push(WorldSettingsScreen.new()))
		add_list_button("Shaders...", func() -> void: menu.push(ShadersScreen.new()))
	add_list_item(Control.new()) # (keeps the pairs even)
	add_done_button()
