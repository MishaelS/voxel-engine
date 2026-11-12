class_name TexturePacksScreen
extends MenuScreen
## Texture packs like Beta 1.7.3's list: "Default" (the game's own textures)
## and every pack in user://texturepacks/ (a .zip, or a folder unpacked,
## laid out like Beta's jar: see TexturePacks), each with its picture
## (pack.png) and its two lines (pack.txt); clicking one picks it. The pick
## is used from the next start. "Open Pack Folder" shows the folder.

const ICON := 32 * UiTheme.PIXEL
const ROW_HEIGHT := 36 * UiTheme.PIXEL

var _note: Label


func _init() -> void:
	title = "Texture Packs"
	columns = 1


func build() -> void:
	var choices := TexturePacks.choices()
	var picked: int = Settings.get_value("texture_pack")
	for i in choices.size():
		var pack := "" if i == 0 else choices[i]
		var index := i
		add_list_item(_row(pack, i == picked, func() -> void:
			Settings.set_value("texture_pack", index)
			menu.replace(TexturePacksScreen.new())))
	_note = Label.new()
	_note.text = Lang.t("A pack is used from the next start. Put Beta 1.7.3 texture packs (.zip) into the pack folder.")
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


## A pack's row: its picture, its name and its two lines; framed when picked.
func _row(pack: String, picked: bool, on_pressed: Callable) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, ROW_HEIGHT)
	button.flat = not picked
	button.pressed.connect(on_pressed)
	var icon := TextureRect.new()
	icon.texture = TexturePacks.icon(pack)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(2, 2) * UiTheme.PIXEL
	icon.size = Vector2(ICON, ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var text := Label.new()
	var about := TexturePacks.description(pack) if pack != "" else Lang.t("The default look of Voxel Engine")
	text.text = (Lang.t("Default") if pack == "" else pack) + ("\n" + about if about != "" else "")
	text.add_theme_color_override("font_color", UiTheme.TEXT_COLOR)
	text.position = Vector2(ICON + 6 * UiTheme.PIXEL, UiTheme.PIXEL)
	text.size = Vector2(UiTheme.WIDE_BUTTON - ICON - 8 * UiTheme.PIXEL, ROW_HEIGHT - 2 * UiTheme.PIXEL)
	text.clip_text = true
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(text)
	return button
