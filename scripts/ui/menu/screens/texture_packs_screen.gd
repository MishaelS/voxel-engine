class_name TexturePacksScreen
extends MenuScreen
## Texture packs like the classic game's screen: "Default" (the game's own
## textures) and every folder in user://texturepacks/ (each with an optional
## pack.txt line describing it); clicking one picks it. The pick is used
## from the next start. "Open Pack Folder" shows the folder.

var _note: Label


func _init() -> void:
	title = "Texture Packs"
	columns = 1


func build() -> void:
	var choices := TexturePacks.choices()
	var picked: int = Settings.get_value("texture_pack")
	for i in choices.size():
		var name := choices[i]
		var text := Lang.t("Default") if i == 0 else name
		var about := _description(name) if i > 0 else Lang.t("The game's own textures")
		if about != "":
			text += " - " + about
		if i == picked:
			text = "> " + text + " <"
		var index := i
		add_list_wide_button(text, func() -> void:
			Settings.set_value("texture_pack", index)
			menu.replace(TexturePacksScreen.new()))
	_note = Label.new()
	_note.text = Lang.t("A pack is used from the next start. Put pack folders into the pack folder, laid out like the game's textures.")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_note.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT * 2)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_list_item(_note)
	add_bottom_row([
		["Open Pack Folder", func() -> void:
			DirAccess.make_dir_recursive_absolute(TexturePacks.DIR)
			OS.shell_open(ProjectSettings.globalize_path(TexturePacks.DIR))],
		["Done", func() -> void: menu.back()],
	])


static func _description(pack: String) -> String:
	var file := TexturePacks.DIR + pack + "/pack.txt"
	if not FileAccess.file_exists(file):
		return ""
	return FileAccess.get_file_as_string(file).strip_edges().get_slice("\n", 0)
