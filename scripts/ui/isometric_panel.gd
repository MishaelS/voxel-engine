class_name IsometricPanel
extends PanelContainer
## The isometric camera's settings right in its view (F6): a panel on the
## right with the angle, facing, zoom, clouds, fog, screenshot size and
## background, changing the view as they are clicked, and a button for an
## isometric screenshot (F7). Z / X and the mouse wheel change facing and
## zoom too; the panel follows.

const P := UiTheme.PIXEL
const WIDTH := 200 * P

var screenshots: Screenshots

var _widgets: Array = [] # [Setting, Control]
var _refresh_wait := 0.0


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -WIDTH - 8 * P
	offset_right = -8 * P
	offset_top = 8 * P
	offset_bottom = -8 * P
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_content_margin_all(6 * P)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3 * P)
	add_child(column)
	var title := Label.new()
	title.text = Lang.t("Isometric Camera")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for setting: Setting in Settings.in_category("isometric"):
		var widget := _make(setting)
		widget.custom_minimum_size = Vector2(WIDTH - 12 * P, UiTheme.BUTTON_HEIGHT)
		column.add_child(widget)
		_widgets.append([setting, widget])
	var shot := Button.new()
	shot.text = Lang.t("Take Screenshot") + " (F7)"
	shot.focus_mode = Control.FOCUS_NONE
	shot.custom_minimum_size = Vector2(WIDTH - 12 * P, UiTheme.BUTTON_HEIGHT)
	shot.pressed.connect(func() -> void: screenshots.render_isometric())
	column.add_child(shot)
	var hint := Label.new()
	hint.text = Lang.t("Z / X: turn, wheel: zoom, F6: back")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size = Vector2(WIDTH - 12 * P, 0)
	hint.add_theme_color_override("font_color", UiTheme.DISABLED_TEXT_COLOR)
	column.add_child(hint)
	refresh()


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
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slider.add_child(label)
		slider.value_changed.connect(func(value: float) -> void:
			setting.set_value(value)
			label.text = setting.display_text())
		return slider
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.pressed.connect(func() -> void:
		if setting.kind == Setting.Kind.BOOL:
			setting.set_value(not setting.get_value())
		else:
			setting.set_value((int(setting.get_value()) + 1) % setting.choices.size())
		refresh())
	return button


func refresh() -> void:
	for pair: Array in _widgets:
		var setting: Setting = pair[0]
		var widget: Control = pair[1]
		if widget is HSlider:
			(widget as HSlider).set_value_no_signal(setting.get_value())
			(widget.get_node("Text") as Label).text = setting.display_text()
		else:
			(widget as Button).text = setting.display_text()


func _process(delta: float) -> void:
	# Facing and zoom change from the keys and the wheel too.
	_refresh_wait -= delta
	if _refresh_wait <= 0.0:
		_refresh_wait = 0.2
		refresh()
