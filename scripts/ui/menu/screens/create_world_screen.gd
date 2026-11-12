class_name CreateWorldScreen
extends MenuScreen
## "Create New World", laid out like Beta 1.7.3's screen: one column in the
## middle of the dirt background - the world name, the seed (its hint
## inside the empty field), then (our additions) the game mode and the
## world type, and "Create New World" / "Cancel" one under the other. An
## empty seed is random, text is hashed.

const MODES := ["Survival", "Creative"]
const TYPES := ["Default", "Random Blocks"]
const P := UiTheme.PIXEL
const GRAY := Color("a0a0a0")

var on_play := Callable()

var _name: LineEdit
var _seed: LineEdit
var _mode := 1
var _type := 0
var _mode_button: Button
var _type_button: Button
var _cheats_button: Button
## Allow Cheats: follows the game mode (on in creative) until set by hand.
var _cheats := true
var _cheats_set := false


func _init(play: Callable) -> void:
	title = "Create New World"
	on_play = play


## Our own layout instead of MenuScreen's list (no darker band, like the
## classic screen).
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.offset_left = -100 * P
	column.offset_right = 100 * P
	column.offset_top = 16 * P
	add_child(column)

	var heading := _label(title, UiTheme.TITLE_COLOR)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	_gap(column, 22)
	column.add_child(_label("World Name", GRAY))
	_gap(column, 2)
	_name = _field("New World")
	column.add_child(_name)
	_gap(column, 10)
	column.add_child(_label("Seed for the World Generator", GRAY))
	_gap(column, 2)
	_seed = _field("")
	_seed.placeholder_text = Lang.t("Blank for a random seed")
	column.add_child(_seed)
	_gap(column, 12)
	_mode_button = _button(column, func() -> void:
		_mode = (_mode + 1) % MODES.size()
		if not _cheats_set:
			_cheats = _mode == 1
		_update_labels())
	_gap(column, 4)
	_cheats_button = _button(column, func() -> void:
		_cheats = not _cheats
		_cheats_set = true
		_update_labels())
	_gap(column, 4)
	_type_button = _button(column, func() -> void:
		_type = (_type + 1) % TYPES.size()
		_update_labels())
	_gap(column, 16)
	var create := _button(column, func() -> void: _create())
	create.text = Lang.t("Create New World")
	_gap(column, 4)
	var cancel := _button(column, func() -> void: menu.back())
	cancel.text = Lang.t("Cancel")

	_update_labels()
	_name.grab_focus.call_deferred()
	_name.select_all.call_deferred()


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = Lang.t(text) if text != "" else ""
	label.add_theme_color_override("font_color", color)
	return label


func _gap(column: VBoxContainer, pixels: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, pixels * P)
	column.add_child(spacer)


func _field(text: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = text
	field.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	field.max_length = 32
	field.text_submitted.connect(func(_text: String) -> void: _create())
	return field


func _button(column: VBoxContainer, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	button.pressed.connect(on_pressed)
	column.add_child(button)
	return button


func _update_labels() -> void:
	_mode_button.text = Lang.t("Game Mode: %s") % Lang.t(MODES[_mode])
	_type_button.text = Lang.t("World Type: %s") % Lang.t(TYPES[_type])
	_cheats_button.text = Lang.t("Allow Cheats: %s") % Lang.t("ON" if _cheats else "OFF")


func _create() -> void:
	var save := WorldSave.create(_name.text, WorldSave.seed_from_text(_seed.text), _type, _mode, _cheats)
	on_play.call(save)
