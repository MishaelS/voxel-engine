class_name CreateWorldScreen
extends MenuScreen
## "Create New World": the world name and the seed (its hint inside the
## empty field), then two buttons a row - game mode and world type, cheats
## and the bonus chest - and "Create New World" / "Cancel" side by side at
## the bottom, over the menu's darker band like the other menu screens. An
## empty seed is random, text is hashed.

const MODES := ["Survival", "Creative"]
## World types: [name, generator (VoxelWorld.Generator), terrain (WorldSave)].
## Default is Beta 1.7.3's world, 128 high with the sea at 64; Tall
## Mountains the same land 256 high.
const TYPES := [
	["Default", VoxelWorld.Generator.BETA, WorldSave.CLASSIC],
	["Tall Mountains", VoxelWorld.Generator.BETA, WorldSave.TALL],
	["Floating Islands", VoxelWorld.Generator.FLOATING_ISLANDS, WorldSave.FLOATING],
	["Island", VoxelWorld.Generator.ISLAND, WorldSave.CLASSIC],
	["Debug Mode", VoxelWorld.Generator.DEBUG, WorldSave.CLASSIC],
	["Random Blocks", VoxelWorld.Generator.RANDOM_BLOCKS, WorldSave.CLASSIC],
]
const P := UiTheme.PIXEL
const GRAY := Color("a0a0a0")
## A button of a row; two of them and the gap are as wide as the fields.
const HALF := UiTheme.HALF_BUTTON
const FIELD_WIDTH := HALF * 2 + COLUMN_GAP

var on_play := Callable()

var _name: LineEdit
var _seed: LineEdit
var _mode := 1
var _type := 0
var _mode_button: Button
var _type_button: Button
var _cheats_button: Button
var _bonus_button: Button
## Allow Cheats: follows the game mode (on in creative) until set by hand.
var _cheats := true
var _cheats_set := false
var _bonus_chest := false


func _init(play: Callable) -> void:
	title = "Create New World"
	columns = 1
	on_play = play


func build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_list_item(column)
	column.add_child(_label("World Name"))
	_gap(column, 2)
	_name = _field("New World")
	column.add_child(_name)
	_gap(column, 8)
	column.add_child(_label("Seed for the World Generator"))
	_gap(column, 2)
	_seed = _field("")
	_seed.placeholder_text = Lang.t("Blank for a random seed")
	column.add_child(_seed)
	_gap(column, 12)
	var row := _row(column)
	_mode_button = _button(row, func() -> void:
		_mode = (_mode + 1) % MODES.size()
		if not _cheats_set:
			_cheats = _mode == 1
		_update_labels())
	_type_button = _button(row, func() -> void:
		_type = (_type + 1) % TYPES.size()
		_update_labels())
	_gap(column, 4)
	row = _row(column)
	_cheats_button = _button(row, func() -> void:
		_cheats = not _cheats
		_cheats_set = true
		_update_labels())
	_bonus_button = _button(row, func() -> void:
		_bonus_chest = not _bonus_chest
		_update_labels())

	add_bottom_row([["Create New World", func() -> void: _create()], ["Cancel", func() -> void: menu.back()]], HALF)

	_update_labels()
	_name.grab_focus.call_deferred()
	_name.select_all.call_deferred()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = Lang.t(text)
	label.add_theme_color_override("font_color", GRAY)
	return label


func _gap(column: VBoxContainer, pixels: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, pixels * P)
	column.add_child(spacer)


func _field(text: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = text
	field.custom_minimum_size = Vector2(FIELD_WIDTH, UiTheme.BUTTON_HEIGHT)
	field.max_length = 32
	field.text_submitted.connect(func(_text: String) -> void: _create())
	return field


func _row(column: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COLUMN_GAP)
	column.add_child(row)
	return row


func _button(row: HBoxContainer, on_pressed: Callable) -> Button:
	var button := _make_button("", on_pressed)
	button.custom_minimum_size = Vector2(HALF, UiTheme.BUTTON_HEIGHT)
	row.add_child(button)
	return button


func _update_labels() -> void:
	_mode_button.text = Lang.t("Game Mode: %s") % Lang.t(MODES[_mode])
	_type_button.text = Lang.t("World Type: %s") % Lang.t(TYPES[_type][0])
	_cheats_button.text = Lang.t("Allow Cheats: %s") % Lang.t("ON" if _cheats else "OFF")
	_bonus_button.text = Lang.t("Bonus Chest: %s") % Lang.t("ON" if _bonus_chest else "OFF")
	# (the debug world is a showcase: no chest in it)
	_bonus_button.disabled = TYPES[_type][1] == VoxelWorld.Generator.DEBUG


func _create() -> void:
	var save := WorldSave.create(_name.text, WorldSave.seed_from_text(_seed.text), TYPES[_type][1], _mode, _cheats,
		TYPES[_type][2])
	save.bonus_chest = _bonus_chest and TYPES[_type][1] != VoxelWorld.Generator.DEBUG
	save.write_level()
	on_play.call(save)
