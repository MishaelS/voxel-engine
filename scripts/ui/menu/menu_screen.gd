class_name MenuScreen
extends Control
## Base of menu screens, laid out like the classic game: a title at the top,
## a two-column list of buttons/options in the middle (scrolls if long) and
## buttons such as "Done" at the bottom.
## Subclasses override build() and use the add_* helpers; options come from
## Setting objects, so any setting gets the same widget everywhere.

const COLUMN_GAP := 4 * UiTheme.PIXEL
const ROW_GAP := 4 * UiTheme.PIXEL

## The Menu that shows this screen (set before build()).
var menu: Menu
var title := ""
## Columns of the option list.
var columns := 2
## Center the list vertically (short screens like the pause menu).
var center_vertically := false

var _list: GridContainer
## The scrolling list area (Menu darkens it on the title screen's background).
var list_area: ScrollContainer
var _bottom: VBoxContainer
## [Setting, Control] pairs, refreshed when the screen is shown again.
var _option_widgets: Array = []


## Override: add the screen's widgets.
func build() -> void:
	pass


## Override to receive raw key presses (e.g. while rebinding a key).
## Return true if the event was used.
func capture_key(_event: InputEventKey) -> bool:
	return false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_top = 16 * UiTheme.PIXEL
	layout.offset_bottom = -8 * UiTheme.PIXEL
	layout.add_theme_constant_override("separation", 10 * UiTheme.PIXEL)
	add_child(layout)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", UiTheme.TITLE_COLOR)
	layout.add_child(title_label)

	var scroll := ScrollContainer.new()
	list_area = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if center_vertically:
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_list = GridContainer.new()
	_list.columns = columns
	_list.add_theme_constant_override("h_separation", COLUMN_GAP)
	_list.add_theme_constant_override("v_separation", ROW_GAP)
	center.add_child(_list)

	_bottom = VBoxContainer.new()
	_bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom.add_theme_constant_override("separation", ROW_GAP)
	var bottom_center := CenterContainer.new()
	bottom_center.add_child(_bottom)
	layout.add_child(bottom_center)

	build()
	refresh()


## Updates every option widget from its current value.
func refresh() -> void:
	for pair: Array in _option_widgets:
		_update_widget(pair[0], pair[1])


# --- Helpers for build() -------------------------------------------------------

## A widget for a Setting in the two-column list: a cycling button for
## toggles and choices, a slider for ranges.
func add_option(setting: Setting) -> Control:
	var widget := make_option(setting)
	_list.add_child(widget)
	return widget


## The widget for a Setting (registered for refresh), not yet placed.
func make_option(setting: Setting) -> Control:
	var widget: Control
	if setting.kind == Setting.Kind.RANGE:
		widget = _make_slider(setting)
	else:
		var button := _make_button("", func() -> void:
			if setting.kind == Setting.Kind.BOOL:
				setting.set_value(not setting.get_value())
			else:
				setting.set_value((int(setting.get_value()) + 1) % setting.choices.size())
			refresh())
		widget = button
	widget.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT)
	if setting.tooltip:
		widget.tooltip_text = setting.tooltip
	_option_widgets.append([setting, widget])
	return widget


## A half-width button in the two-column list.
func add_list_button(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text, on_pressed)
	button.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT)
	_list.add_child(button)
	return button


## A wide button in the list (for one-column screens).
func add_list_wide_button(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text, on_pressed)
	button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	_list.add_child(button)
	return button


## Any control in the list (labels, key buttons).
func add_list_item(control: Control) -> void:
	_list.add_child(control)


## A wide button at the bottom of the screen.
func add_bottom_button(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text, on_pressed)
	button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	_bottom.add_child(button)
	return button


## A row of buttons at the bottom: [[text, callable], ...], each `width` wide.
func add_bottom_row(buttons: Array, width: float = UiTheme.HALF_BUTTON) -> Array[Button]:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", COLUMN_GAP)
	var result: Array[Button] = []
	for entry: Array in buttons:
		var button := _make_button(entry[0], entry[1])
		# (a third value: that button's own width)
		button.custom_minimum_size = Vector2(entry[2] if entry.size() > 2 else width, UiTheme.BUTTON_HEIGHT)
		row.add_child(button)
		result.append(button)
	_bottom.add_child(row)
	return result


func add_done_button() -> Button:
	return add_bottom_button("Done", func() -> void: menu.back())


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.pressed.connect(on_pressed)
	return button


## Slider with the value written over it, like the classic options screen.
func _make_slider(setting: Setting) -> Control:
	var slider := HSlider.new()
	slider.min_value = setting.min_value
	slider.max_value = setting.max_value
	slider.step = setting.step
	slider.focus_mode = Control.FOCUS_NONE
	slider.value = setting.get_value()
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


func _update_widget(setting: Setting, widget: Control) -> void:
	if widget is HSlider:
		widget.set_value_no_signal(setting.get_value())
		(widget.get_node("Text") as Label).text = setting.display_text()
	elif widget is Button:
		widget.text = setting.display_text()
