class_name ControlsScreen
extends MenuScreen
## Mouse options and key bindings. Click a key button, then press the new
## key (Esc cancels). Keys used by two actions are shown in red.

const WAITING_TEXT := "> %s <"

var _key_buttons := {} # action -> Button
var _waiting_action := ""


func _init() -> void:
	title = "Controls"


func build() -> void:
	for setting: Setting in Settings.in_category("controls"):
		add_option(setting)
	for entry: Array in KeyBindings.ACTIONS:
		var action: String = entry[0]
		var label := Label.new()
		label.text = entry[1]
		label.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_list_item(label)
		var button := _make_button("", func() -> void: _start_waiting(action))
		button.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT)
		_key_buttons[action] = button
		add_list_item(button)
	add_bottom_button("Reset Keys", func() -> void:
		KeyBindings.reset_all()
		Settings.save_settings()
		_waiting_action = ""
		refresh())
	add_done_button()


func refresh() -> void:
	super.refresh()
	for action: String in _key_buttons:
		var button: Button = _key_buttons[action]
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
