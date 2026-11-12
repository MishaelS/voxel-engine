class_name PlayerSettingsScreen
extends MenuScreen
## "Player Settings": the name (shown above the head in network games, in
## the chat and the Tab list), its color (the game's chat colors or a
## rainbow), and the skin: the player's own from a PNG file (64 x 64 or the
## classic 64 x 32) or the default one, with a preview of the front and the
## back. Kept by PlayerProfile (and Net for the name).

const P := UiTheme.PIXEL

var _name: LineEdit
var _color_button: Button
var _status: Label
var _preview: SkinPreview


func _init() -> void:
	title = "Player Settings"
	columns = 1


func build() -> void:
	_preview = SkinPreview.new()
	_preview.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, 84 * P)
	add_list_item(_preview)
	_name = LineEdit.new()
	_name.text = Net.player_name
	_name.max_length = 16
	_name.placeholder_text = Lang.t("Your Name")
	_name.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	_name.text_changed.connect(func(text: String) -> void:
		var clean := text.strip_edges()
		if clean != "":
			Net.player_name = clean
			Net.save_config()
		_preview.queue_redraw())
	add_list_item(_name)
	_color_button = add_list_wide_button("", func() -> void:
		PlayerProfile.name_color = (PlayerProfile.name_color + 1) % PlayerProfile.COLORS.size()
		PlayerProfile.save_profile()
		Net.send_look()
		_update())
	add_list_wide_button("Choose Skin...", _choose_skin)
	add_list_wide_button("Default Skin", func() -> void:
		PlayerProfile.reset_skin()
		_status.text = ""
		_preview.queue_redraw())
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("ff7070"))
	add_list_item(_status)
	add_done_button()
	_update()


func _update() -> void:
	_color_button.text = Lang.t("Name Color: %s") % Lang.t(PlayerProfile.COLORS[PlayerProfile.name_color][0])
	_preview.queue_redraw()


func _choose_skin() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png ; PNG"])
	dialog.use_native_dialog = true
	dialog.title = Lang.t("Choose Skin...")
	dialog.file_selected.connect(func(path: String) -> void:
		var error := PlayerProfile.load_skin_file(path)
		_status.text = Lang.t(error) if error != "" else ""
		_preview.queue_redraw()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## The skin seen from the front and the back (the classic unfolded parts put
## together), the name above in its color.
class SkinPreview:
	extends Control

	const SCALE := 2.0 # screen pixels per skin pixel, times the GUI pixel

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(_delta: float) -> void:
		if PlayerProfile.name_color == PlayerProfile.RAINBOW:
			queue_redraw()

	func _draw() -> void:
		var skin := PlayerProfile.skin_texture()
		var unit := SCALE * UiTheme.PIXEL
		var figure := Vector2(16, 32) * unit
		var gap := 12.0 * unit
		var left := (size.x - figure.x * 2.0 - gap) / 2.0
		var top := size.y - figure.y - 2.0 * unit
		_figure(skin, Vector2(left, top), unit, true)
		_figure(skin, Vector2(left + figure.x + gap, top), unit, false)
		var font := UiTheme.font()
		var text := Net.player_name
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE).x
		draw_string(font, Vector2((size.x - width) / 2.0, top - 4.0 * unit), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UiTheme.FONT_SIZE, PlayerProfile.color_of(PlayerProfile.name_color))

	## One side of the figure: [skin rect, place in the figure (skin pixels)],
	## the hat, jacket, sleeves and trousers layers over the base.
	func _figure(skin: Texture2D, origin: Vector2, unit: float, front: bool) -> void:
		var parts := [
			[Rect2(8, 8, 8, 8), Vector2(4, 0)], [Rect2(20, 20, 8, 12), Vector2(4, 8)],
			[Rect2(44, 20, 4, 12), Vector2(0, 8)], [Rect2(36, 52, 4, 12), Vector2(12, 8)],
			[Rect2(4, 20, 4, 12), Vector2(4, 20)], [Rect2(20, 52, 4, 12), Vector2(8, 20)],
			[Rect2(40, 8, 8, 8), Vector2(4, 0)], [Rect2(20, 36, 8, 12), Vector2(4, 8)],
			[Rect2(44, 36, 4, 12), Vector2(0, 8)], [Rect2(52, 52, 4, 12), Vector2(12, 8)],
			[Rect2(4, 36, 4, 12), Vector2(4, 20)], [Rect2(4, 52, 4, 12), Vector2(8, 20)],
		]
		if not front:
			# The back: each part's back face (its front + the width of the
			# front and a side), and right and left swapped.
			parts = [
				[Rect2(24, 8, 8, 8), Vector2(4, 0)], [Rect2(32, 20, 8, 12), Vector2(4, 8)],
				[Rect2(52, 20, 4, 12), Vector2(12, 8)], [Rect2(44, 52, 4, 12), Vector2(0, 8)],
				[Rect2(12, 20, 4, 12), Vector2(8, 20)], [Rect2(28, 52, 4, 12), Vector2(4, 20)],
				[Rect2(56, 8, 8, 8), Vector2(4, 0)], [Rect2(32, 36, 8, 12), Vector2(4, 8)],
				[Rect2(52, 36, 4, 12), Vector2(12, 8)], [Rect2(60, 52, 4, 12), Vector2(0, 8)],
				[Rect2(12, 36, 4, 12), Vector2(8, 20)], [Rect2(12, 52, 4, 12), Vector2(4, 20)],
			]
		for part: Array in parts:
			var source: Rect2 = part[0]
			draw_texture_rect_region(skin, Rect2(origin + part[1] * unit, source.size * unit), source)
