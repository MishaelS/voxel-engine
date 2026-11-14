class_name Hotbar
extends Control
## The hotbar at the bottom of the screen: the first 9 slots of the
## player's inventory with block icons, counts and a selection frame, drawn
## with hotbar.png / hotbarSelector.png. When the selection changes, the
## block name shows above it for a moment; short notes from the player
## (Player.status_message: "You can only sleep at night") show there too,
## like the game's action bar.
## Slots are chosen with 1-9 or the mouse wheel (see BlockInteraction).

signal selection_changed(slot: int)

const SLOT_COUNT := 9
const NAME_SECONDS := 2.0
const NAME_FADE := 0.5
const STATUS_SECONDS := 3.0
const P := UiTheme.PIXEL


@export var player: Player
## Selected slot; stored on the player (it decides what is in hand).
var selected: int:
	get:
		return player.selected_slot if player else 0
	set(value):
		if player:
			player.selected_slot = value

var _icons: Array[ItemSlotView] = []
var _selector: TextureRect
var _name_label: Label
var _name_shown_at := -100.0
var _name_seconds := NAME_SECONDS


func _ready() -> void:
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 182x22 texture pixels, centered at the bottom.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -91 * P
	offset_right = 91 * P
	offset_top = -23 * P
	offset_bottom = -1 * P

	var background := TextureRect.new()
	background.texture = UiTheme.gui_texture("hotbar.png")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	for i in SLOT_COUNT:
		var icon := ItemSlotView.new()
		icon.position = Vector2(3 + i * 20, 3) * P
		add_child(icon)
		_icons.append(icon)

	_selector = TextureRect.new()
	_selector.texture = UiTheme.gui_texture("hotbarSelector.png")
	_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_selector)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Above the hearts and the air bubbles (the game's: 59 pixels above the bottom).
	_name_label.position = Vector2(0, -37 * P)
	_name_label.size = Vector2(182 * P, 10 * P)
	_name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH # long notes stay centered
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	if player:
		player.inventory.changed.connect(_refresh)
		player.game_mode_changed.connect(func(_mode: Player.GameMode) -> void: _refresh())
		player.status_message.connect(show_status)
	Settings.changed.connect(func(key: String, _value: Variant) -> void:
		if key == "gui_scale":
			_refresh.call_deferred())
	_refresh()


func _process(_delta: float) -> void:
	var age := Time.get_ticks_msec() / 1000.0 - _name_shown_at
	_name_label.modulate.a = clampf(1.0 - (age - _name_seconds) / NAME_FADE, 0.0, 1.0)


func selected_block() -> int:
	return player.held_block() if player else Blocks.AIR


func select(slot: int) -> void:
	selected = posmod(slot, SLOT_COUNT)
	_refresh()
	_show_name()
	selection_changed.emit(selected)


## Wheel: +1 next slot, -1 previous (wraps around like the classic game).
func scroll(direction: int) -> void:
	select(selected + direction)


## Pick block (middle click) like the classic game: select the hotbar slot
## that has the block; otherwise in creative put it into the selected slot
## (or the first empty one), in survival swap it in from the main inventory.
func pick(block_id: int) -> void:
	block_id = Blocks.item_of(block_id) # oriented / lit variants: the block itself
	if block_id == Blocks.id_of("water"):
		return
	var inventory := player.inventory
	var existing := inventory.find(block_id, 0, SLOT_COUNT)
	if existing >= 0:
		select(existing)
		return
	if player.is_creative():
		var target := selected
		if not inventory.is_empty_slot(target):
			for slot in SLOT_COUNT:
				if inventory.is_empty_slot(slot):
					target = slot
					break
		inventory.set_slot(target, block_id, 1)
		select(target)
	else:
		var stored := inventory.find(block_id, SLOT_COUNT)
		if stored >= 0:
			inventory.swap(stored, selected)
			_show_name()


func _refresh() -> void:
	if player == null:
		return
	for i in SLOT_COUNT:
		_icons[i].set_item(player.inventory.id_at(i), player.inventory.count_at(i), true, player.inventory.damage_at(i))
	_selector.position = Vector2(-1 + selected * 20, -1) * P


func _show_name() -> void:
	var id := selected_block()
	_name_label.text = Items.display_name(id) if id != Blocks.AIR else ""
	_name_shown_at = Time.get_ticks_msec() / 1000.0
	_name_seconds = NAME_SECONDS


## A note over the hotbar for a few seconds, in the held item name's place.
func show_status(text: String) -> void:
	_name_label.text = text
	_name_shown_at = Time.get_ticks_msec() / 1000.0
	_name_seconds = STATUS_SECONDS
