class_name VideoSettingsScreen
extends MenuScreen
## "Video Settings", laid out like the classic game with its well-known
## optimization mod: the main options in two columns (Graphics, Render
## Distance, Smooth Lighting, Max Framerate, VSync, View Bobbing, GUI
## Scale, Brightness, Clouds, Fullscreen, Fog, Fog Distance), the sections
## Quality, Details, Performance, Animations, Other and Shaders, and quick
## presets for weak and powerful computers.

const SECTIONS := [
	["Quality...", "Quality", "quality"],
	["Details...", "Details", "details"],
	["Performance...", "Performance", "performance"],
	["Animations...", "Animations", "animations"],
	["Other...", "Other", "other"],
]
const PRESET_HINTS := {
	"Low": "For weak computers: fast graphics, short render distance, Classic shaders",
	"Medium": "Balanced: fancy graphics, Classic shaders",
	"High": "For powerful computers: far render distance, Dynamic Lighting",
}


func _init() -> void:
	title = "Video Settings"


func build() -> void:
	for setting: Setting in Settings.in_category("video"):
		add_option(setting)
	for section: Array in SECTIONS:
		add_list_button(section[0], func() -> void: menu.push(SettingsListScreen.new(section[1], section[2])))
	add_list_button("Shaders...", func() -> void: menu.push(ShadersScreen.new()))

	var row: Array = []
	for preset: String in Settings.PRESETS:
		row.append([Lang.t("Preset: %s") % Lang.t(preset), func() -> void:
			Settings.apply_preset(preset)
			refresh()])
	var buttons := add_bottom_row(row, 98 * UiTheme.PIXEL)
	var presets := Settings.PRESETS.keys()
	for i in buttons.size():
		buttons[i].tooltip_text = PRESET_HINTS[presets[i]]
	add_done_button()
