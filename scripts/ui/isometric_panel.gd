class_name IsometricPanel
extends Control
## The World Diorama's screen (F6), over the whole view: a close button at
## the top left, the settings in a column on the right (changing the view
## as they are used), and at the bottom the hint, the turn buttons, Take
## Screenshot (F7) and a button opening the screenshots folder.
## On the view itself: drag to move, right-drag (or Shift+drag) to turn and
## tilt, the wheel (or a pinch) to zoom.

const P := UiTheme.PIXEL
const COLUMN_WIDTH := 150 * P
const GAP := 3 * P
## Degrees per pixel when dragging to turn and tilt.
const TURN_SPEED := 0.35
const TILT_SPEED := 0.25
## How long the "saved" note stays (seconds).
const NOTE_SECONDS := 8.0

enum Drag { NONE, MOVE, TURN }

var screenshots: Screenshots
var camera: IsometricCamera

var _widgets: Array = [] # [Setting, Control]
var _shader_button: Button
var _shot_button: Button
var _note: Label
var _note_time := 0.0
var _refresh_wait := 0.0
var _drag := Drag.NONE
var _drag_turn := 0.0
var _drag_tilt := 0.0


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	_build_top()
	_build_column()
	_build_bottom()
	screenshots.saved.connect(_on_saved)
	refresh()


func _build_top() -> void:
	var close := _button("X", func() -> void: screenshots.set_isometric(false))
	close.tooltip_text = Lang.t("Close") + " (F6)"
	close.custom_minimum_size = Vector2(UiTheme.BUTTON_HEIGHT, UiTheme.BUTTON_HEIGHT)
	close.position = Vector2(8 * P, 8 * P)
	add_child(close)
	var title := Label.new()
	title.text = Lang.t("World Diorama")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.TITLE_COLOR)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -100 * P
	title.offset_right = 100 * P
	title.offset_top = 12 * P
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)


## The settings: a slider for ranges, a cycling button for the rest.
func _build_column() -> void:
	# (scrolls when the screen is too short for all of it)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_left = -COLUMN_WIDTH - 8 * P
	scroll.offset_right = -8 * P
	scroll.offset_top = 8 * P
	scroll.offset_bottom = -8 * P
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(column)
	var center := _button(Lang.t("Center Camera"), func() -> void: screenshots.center_camera())
	center.custom_minimum_size = Vector2(COLUMN_WIDTH, UiTheme.BUTTON_HEIGHT)
	column.add_child(center)
	for key: String in ["iso_area", "iso_zoom", "iso_tilt", "iso_time", "iso_fog_amount",
			"iso_clouds", "iso_players", "iso_mobs"]:
		_add_setting(column, Settings.get_setting(key))
	_shader_button = _button("", _next_shader_pack)
	_shader_button.custom_minimum_size = Vector2(COLUMN_WIDTH, UiTheme.BUTTON_HEIGHT)
	_shader_button.clip_text = true
	column.add_child(_shader_button)
	for key: String in ["iso_render_size", "iso_background"]:
		_add_setting(column, Settings.get_setting(key))


func _build_bottom() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GAP)
	box.alignment = BoxContainer.ALIGNMENT_END
	# Centered in the room left of the settings.
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 8 * P
	box.offset_right = -COLUMN_WIDTH - 16 * P
	box.offset_top = -60 * P
	box.offset_bottom = -8 * P
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", UiTheme.HOVER_TEXT_COLOR)
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0, 0, 0, 0.5)
	backdrop.set_content_margin_all(2 * P)
	_note.add_theme_stylebox_override("normal", backdrop)
	_note.visible = false
	box.add_child(_note)
	var hint := Label.new()
	hint.text = Lang.t("Click and hold to move and rotate")
	hint.tooltip_text = Lang.t("Drag: move. Right-drag or Shift+drag: rotate and tilt. Wheel: zoom.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var square := Vector2(UiTheme.BUTTON_HEIGHT, UiTheme.BUTTON_HEIGHT)
	var left := _button("<", func() -> void: screenshots.rotate_view(-90))
	left.tooltip_text = Lang.t("Rotate Left") + " (Z)"
	left.custom_minimum_size = square
	row.add_child(left)
	_shot_button = _button(Lang.t("Take Screenshot"), func() -> void: screenshots.render_isometric())
	_shot_button.tooltip_text = Lang.t("Take Screenshot") + " (F7)"
	_shot_button.custom_minimum_size = Vector2(130 * P, UiTheme.BUTTON_HEIGHT)
	row.add_child(_shot_button)
	var right := _button(">", func() -> void: screenshots.rotate_view(90))
	right.tooltip_text = Lang.t("Rotate Right") + " (X)"
	right.custom_minimum_size = square
	row.add_child(right)
	var folder := _button("", func() -> void: screenshots.open_folder())
	folder.name = "OpenFolder"
	folder.icon = _folder_icon()
	folder.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	folder.tooltip_text = Lang.t("Open Screenshots Folder")
	folder.custom_minimum_size = square
	row.add_child(folder)


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW
	button.pressed.connect(on_pressed)
	return button


func _add_setting(column: Control, setting: Setting) -> void:
	var widget := _make(setting)
	widget.custom_minimum_size = Vector2(COLUMN_WIDTH, UiTheme.BUTTON_HEIGHT)
	widget.mouse_default_cursor_shape = Control.CURSOR_ARROW
	column.add_child(widget)
	_widgets.append([setting, widget])


## A cycling button for choices and toggles, a slider for ranges (like the
## options screens).
func _make(setting: Setting) -> Control:
	if setting.kind == Setting.Kind.RANGE:
		var slider := HSlider.new()
		slider.min_value = setting.min_value
		slider.max_value = setting.max_value
		slider.step = setting.step
		slider.focus_mode = Control.FOCUS_NONE
		var label := Label.new()
		label.name = "Text"
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slider.add_child(label)
		slider.value_changed.connect(func(value: float) -> void:
			setting.set_value(value)
			label.text = setting.display_text())
		return slider
	var button := _button("", func() -> void: pass)
	button.clip_text = true
	button.pressed.connect(func() -> void:
		if setting.kind == Setting.Kind.BOOL:
			setting.set_value(not setting.get_value())
		else:
			setting.set_value((int(setting.get_value()) + 1) % setting.choices.size())
		refresh())
	return button


## The lighting style: the next shader pack (the same choice as in Shaders).
func _next_shader_pack() -> void:
	var packs := ShaderPacks.packs
	if packs.is_empty():
		return
	ShaderPacks.select(packs[(packs.find(ShaderPacks.current) + 1) % packs.size()])
	refresh()


## A small pixel folder for the open-folder button.
static func _folder_icon() -> ImageTexture:
	var rows := [
		"..####......",
		".#OOOO#.....",
		"############",
		"#YYYYYYYYYY#",
		"#YYYYYYYYYY#",
		"#YYYYYYYYYY#",
		"#YYYYYYYYYY#",
		"############",
	]
	var colors := {"#": Color("3f2a10"), "O": Color("c89a3c"), "Y": Color("e8bf5a")}
	var image := Image.create(12, 8, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in (rows[y] as String).length():
			var c: String = rows[y][x]
			image.set_pixel(x, y, colors.get(c, Color(0, 0, 0, 0)))
	image.resize(12 * P, 8 * P, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


func refresh() -> void:
	for pair: Array in _widgets:
		var setting: Setting = pair[0]
		var widget: Control = pair[1]
		if widget is HSlider:
			(widget as HSlider).set_value_no_signal(setting.get_value())
			(widget.get_node("Text") as Label).text = setting.display_text()
		else:
			(widget as Button).text = setting.display_text()
	if _shader_button and ShaderPacks.current:
		_shader_button.text = "%s: %s" % [Lang.t("Lighting"), Lang.t(ShaderPacks.current.name)]


# --- The view: drag, turn, zoom -----------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if button.pressed:
					var turn := button.button_index == MOUSE_BUTTON_RIGHT \
						or (button.button_index == MOUSE_BUTTON_LEFT and button.shift_pressed)
					_drag = Drag.TURN if turn else Drag.MOVE
					_drag_turn = Settings.get_value("iso_rotation")
					_drag_tilt = Settings.get_value("iso_tilt")
				else:
					_drag = Drag.NONE
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					camera.zoom(-1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		accept_event()
	elif event is InputEventMouseMotion and _drag != Drag.NONE:
		var moved := (event as InputEventMouseMotion).relative
		if _drag == Drag.MOVE:
			camera.drag(moved, get_viewport_rect().size.y)
		else:
			# Like turning a model on a table: it follows the mouse.
			_drag_turn = fposmod(_drag_turn - moved.x * TURN_SPEED, 360.0)
			_drag_tilt = clampf(_drag_tilt + moved.y * TILT_SPEED, 10.0, 80.0)
			Settings.set_value("iso_rotation", _drag_turn)
			Settings.set_value("iso_tilt", _drag_tilt)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var factor := (event as InputEventMagnifyGesture).factor
		Settings.set_value("iso_zoom", float(Settings.get_value("iso_zoom")) / maxf(factor, 0.01))
		accept_event()


func _on_saved(path: String) -> void:
	if path.is_empty():
		_show_note(Lang.t("Couldn't save the screenshot"))
	else:
		_show_note(Lang.t("Saved to %s") % ProjectSettings.globalize_path(path))


func _show_note(text: String) -> void:
	_note.text = text
	_note.visible = true
	_note_time = NOTE_SECONDS


func _process(delta: float) -> void:
	if screenshots.is_rendering():
		_show_note(Lang.t("Rendering diorama screenshot..."))
		_note_time = 0.1
	elif _note_time > 0.0:
		_note_time -= delta
		_note.visible = _note_time > 0.0
	_shot_button.disabled = screenshots.is_rendering()
	# The settings change from the keys and the wheel too.
	_refresh_wait -= delta
	if _refresh_wait <= 0.0:
		_refresh_wait = 0.2
		refresh()
