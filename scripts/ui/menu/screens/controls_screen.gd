class_name ControlsScreen
extends MenuScreen
## "Controls", laid out like the modern classic game: the mouse options on
## top, then every key binding grouped by category, each row with the
## action, its key and a Reset button. Click a key, then press the new key
## (Esc cancels). Keys used by two actions are shown in red.

const WAITING_TEXT := "> %s <"
const LABEL_WIDTH := 150 * UiTheme.PIXEL
const KEY_WIDTH := 75 * UiTheme.PIXEL
const RESET_WIDTH := 50 * UiTheme.PIXEL

var _key_buttons := {}   # action -> Button
var _reset_buttons := {} # action -> Button
var _waiting_action := ""


func _init() -> void:
	title = "Controls"
	columns = 1


func build() -> void:
	# Mouse options, two per row.
	var options := Settings.in_category("controls")
	for i in range(0, options.size(), 2):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", COLUMN_GAP)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for setting: Setting in options.slice(i, i + 2):
			row.add_child(make_option(setting))
		add_list_item(row)

	var category := ""
	for entry: Array in KeyBindings.ACTIONS:
		if entry[2] != category:
			category = entry[2]
			var header := Label.new()
			header.text = category
			header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			header.custom_minimum_size = Vector2(0, UiTheme.BUTTON_HEIGHT)
			header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			add_list_item(header)
		add_list_item(_binding_row(entry[0], entry[1]))

	add_bottom_row([
		["Reset Keys", func() -> void:
			KeyBindings.reset_all()
			Settings.save_settings()
			_waiting_action = ""
			refresh()],
		["Done", func() -> void: menu.back()],
	])


func _binding_row(action: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COLUMN_GAP)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, UiTheme.BUTTON_HEIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	row.add_child(label)
	var key := _make_button("", func() -> void: _start_waiting(action))
	key.custom_minimum_size = Vector2(KEY_WIDTH, UiTheme.BUTTON_HEIGHT)
	row.add_child(key)
	var reset := _make_button("Reset", func() -> void:
		KeyBindings.reset(action)
		Settings.save_settings()
		refresh())
	reset.custom_minimum_size = Vector2(RESET_WIDTH, UiTheme.BUTTON_HEIGHT)
	row.add_child(reset)
	_key_buttons[action] = key
	_reset_buttons[action] = reset
	return row


func refresh() -> void:
	super.refresh()
	for action: String in _key_buttons:
		var button: Button = _key_buttons[action]
		(_reset_buttons[action] as Button).disabled = KeyBindings.is_default(action)
		if action == _waiting_action:
			button.text = WAITING_TEXT % KeyBindings.key_name(action)
			button.add_theme_color_override("font_color", UiTheme.HOVER_TEXT_COLOR)
		else:
			button.text = KeyBindings.key_name(action)
			if KeyBindings.has_conflict(action):
				button.add_theme_color_override("font_color", UiTheme.WARNING_COLOR)
			else:
				button.remove_theme_color_override("font_color")


func capture_key(event: InputEventKey) -> bool:
	if _waiting_action == "":
		return false
	if event.keycode != KEY_ESCAPE:
		KeyBindings.rebind(_waiting_action, event.physical_keycode)
		Settings.save_settings()
	_waiting_action = ""
	refresh()
	return true


func _start_waiting(action: String) -> void:
	_waiting_action = action
	refresh()
