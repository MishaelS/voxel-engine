class_name KeyBindings
extends RefCounted
## Rebindable keys. The defaults come from the input map in project.godot;
## a rebound action gets exactly one key (like the classic game). Bindings
## are saved by Settings in the [keys] section of settings.cfg as physical
## key codes, so they follow key positions, not layout letters.

const SECTION := "keys"

## [action, label, category] in the order shown on the Controls screen.
const ACTIONS := [
	["move_forward", "Walk Forwards", "Movement"],
	["move_back", "Walk Backwards", "Movement"],
	["move_left", "Strafe Left", "Movement"],
	["move_right", "Strafe Right", "Movement"],
	["jump", "Jump", "Movement"],
	["sneak", "Sneak", "Movement"],
	["sprint", "Sprint", "Movement"],
	["inventory", "Open Inventory", "Inventory"],
	["hotbar_1", "Hotbar Slot 1", "Inventory"],
	["hotbar_2", "Hotbar Slot 2", "Inventory"],
	["hotbar_3", "Hotbar Slot 3", "Inventory"],
	["hotbar_4", "Hotbar Slot 4", "Inventory"],
	["hotbar_5", "Hotbar Slot 5", "Inventory"],
	["hotbar_6", "Hotbar Slot 6", "Inventory"],
	["hotbar_7", "Hotbar Slot 7", "Inventory"],
	["hotbar_8", "Hotbar Slot 8", "Inventory"],
	["hotbar_9", "Hotbar Slot 9", "Inventory"],
	["open_chat", "Open Chat", "Multiplayer"],
	["open_command", "Open Command", "Multiplayer"],
	["sun_raise", "Time Forward", "World"],
	["sun_lower", "Time Backward", "World"],
	["sun_rotate_left", "Rotate Sun Path Left", "World"],
	["sun_rotate_right", "Rotate Sun Path Right", "World"],
	["next_day", "Next Day", "World"],
	["regenerate_world", "Regenerate World", "World"],
	["hide_gui", "Hide GUI", "Camera"],
	["screenshot", "Take Screenshot", "Camera"],
	["isometric_view", "Isometric Camera", "Camera"],
	["isometric_screenshot", "Isometric Screenshot", "Camera"],
	["isometric_rotate_left", "Isometric: Rotate Left", "Camera"],
	["isometric_rotate_right", "Isometric: Rotate Right", "Camera"],
	["tick_freeze", "Freeze Ticks", "Debug"],
	["tick_step", "Step One Tick", "Debug"],
	["toggle_debug", "Debug Screen", "Debug"],
	["toggle_vsync", "Toggle VSync", "Debug"],
	["toggle_fullscreen", "Toggle Fullscreen", "Debug"],
]

static var _defaults := {} # action -> Array[InputEvent]


## Remembers the project defaults (call once before loading saved keys).
static func capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for entry: Array in ACTIONS:
		_defaults[entry[0]] = InputMap.action_get_events(entry[0]).duplicate()


static func _first_key(action: String) -> InputEventKey:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event
	return null


static func physical_keycode(action: String) -> int:
	var event := _first_key(action)
	return event.physical_keycode if event else KEY_NONE


## Name of the physical key (US layout names, so every key reads the same
## on any keyboard layout), e.g. "W", "Space", "Slash", "F11".
static func key_name(action: String) -> String:
	var event := _first_key(action)
	if event == null:
		return "NONE"
	var text := OS.get_keycode_string(event.physical_keycode)
	if event.alt_pressed:
		text = "Alt+" + text
	return text


static func rebind(action: String, physical: Key) -> void:
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical
	InputMap.action_add_event(action, event)


static func is_default(action: String) -> bool:
	var defaults: Array = _defaults.get(action, [])
	var current := InputMap.action_get_events(action)
	if defaults.size() != current.size():
		return false
	for i in defaults.size():
		if not defaults[i].is_match(current[i], true):
			return false
	return true


static func reset(action: String) -> void:
	InputMap.action_erase_events(action)
	for event: InputEvent in _defaults.get(action, []):
		InputMap.action_add_event(action, event)


static func reset_all() -> void:
	for entry: Array in ACTIONS:
		reset(entry[0])


## True if another action uses the same key.
static func has_conflict(action: String) -> bool:
	var key := physical_keycode(action)
	if key == KEY_NONE:
		return false
	for entry: Array in ACTIONS:
		if entry[0] != action and physical_keycode(entry[0]) == key:
			return true
	return false


static func save_to(config: ConfigFile) -> void:
	for entry: Array in ACTIONS:
		if not is_default(entry[0]):
			config.set_value(SECTION, entry[0], physical_keycode(entry[0]))


static func load_from(config: ConfigFile) -> void:
	if not config.has_section(SECTION):
		return
	for action: String in config.get_section_keys(SECTION):
		if InputMap.has_action(action):
			rebind(action, config.get_value(SECTION, action))
