class_name CreateWorldScreen
extends MenuScreen
## "Create New World": world name, seed (empty = random, text is hashed),
## game mode and world type. Creates the save folder and starts playing.

const MODES := ["Survival", "Creative"]
const MODE_HINTS := ["Search for resources, craft, build", "Unlimited blocks, flying, instant breaking"]
const TYPES := ["Default", "Random Blocks"]

var on_play := Callable()

var _name: LineEdit
var _seed: LineEdit
var _mode := 1
var _type := 0
var _mode_button: Button
var _type_button: Button
var _hint: Label


func _init(play: Callable) -> void:
	title = "Create New World"
	columns = 1
	on_play = play


func build() -> void:
	_name = _field("World Name", "New World", "")
	_seed = _field("Seed for the World Generator", "", "Leave blank for a random seed")
	_mode_button = add_list_wide_button("", func() -> void:
		_mode = (_mode + 1) % MODES.size()
		_update_labels())
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color("a0a0a0"))
	add_list_item(_hint)
	_type_button = add_list_wide_button("", func() -> void:
		_type = (_type + 1) % TYPES.size()
		_update_labels())
	add_bottom_row([
		["Create New World", func() -> void: _create()],
		["Cancel", func() -> void: menu.back()],
	])
	_update_labels()
	_name.grab_focus.call_deferred()
	_name.select_all.call_deferred()


func _field(caption: String, text: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", Color("a0a0a0"))
	add_list_item(label)
	var field := LineEdit.new()
	field.text = text
	field.placeholder_text = placeholder
	field.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	field.max_length = 32
	field.text_submitted.connect(func(_text: String) -> void: _create())
	add_list_item(field)
	return field


func _update_labels() -> void:
	_mode_button.text = Lang.t("Game Mode: %s") % Lang.t(MODES[_mode])
	_hint.text = MODE_HINTS[_mode]
	_type_button.text = Lang.t("World Type: %s") % Lang.t(TYPES[_type])


func _create() -> void:
	var save := WorldSave.create(_name.text, WorldSave.seed_from_text(_seed.text), _type, _mode)
	on_play.call(save)
