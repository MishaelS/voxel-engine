class_name VideoSettingsScreen
extends MenuScreen
## "Video Settings", laid out like the classic game with its well-known
## optimization mod: the main options in two columns (Graphics, Render
## Distance, Smooth Lighting, Max Framerate, VSync, View Bobbing, GUI
## Scale, Brightness, Clouds, Fullscreen, Fog, Fog Distance), the sections
## Quality, Details, Performance, Animations, Other and Shaders (shader
## packs are only switched there, by hand).

const SECTIONS := [
	["Quality...", "Quality", "quality"],
	["Details...", "Details", "details"],
	["Performance...", "Performance", "performance"],
	["Animations...", "Animations", "animations"],
	["Other...", "Other", "other"],
]


func _init() -> void:
	title = "Video Settings"


func build() -> void:
	for setting: Setting in Settings.in_category("video"):
		add_option(setting)
	for section: Array in SECTIONS:
		add_list_button(section[0], func() -> void: menu.push(SettingsListScreen.new(section[1], section[2])))
	add_list_button("Shaders...", func() -> void: menu.push(ShadersScreen.new()))
	add_done_button()
