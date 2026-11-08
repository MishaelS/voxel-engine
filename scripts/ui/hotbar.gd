class_name Hotbar
extends Control
## The hotbar at the bottom of the screen: 9 slots with block icons and a
## selection frame, drawn with hotbar.png / hotbarSelector.png. When the
## selection changes, the block name shows above it for a moment.
## Slots are chosen with 1-9 or the mouse wheel (see BlockInteraction).

signal selection_changed(slot: int)

const SLOT_COUNT := 9
const NAME_SECONDS := 2.0
const NAME_FADE := 0.5
const P := UiTheme.PIXEL

## Starting blocks of the slots (registry names).
const DEFAULT_BLOCKS := [
	"grass_plains", "dirt", "stone", "cobblestone", "oak_planks",
	"oak_log", "glass", "oak_leaves", "sand",
]

var slots := PackedInt32Array()
var selected := 0

var _icons: Array[TextureRect] = []
var _selector: TextureRect
var _name_label: Label
var _name_shown_at := -100.0


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
		var icon := TextureRect.new()
		icon.position = Vector2(3 + i * 20, 3) * P
		icon.size = Vector2(16, 16) * P
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		_icons.append(icon)

	_selector = TextureRect.new()
	_selector.texture = UiTheme.gui_texture("hotbarSelector.png")
	_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_selector)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(0, -16 * P)
	_name_label.size = Vector2(182 * P, 10 * P)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	for block_name: String in DEFAULT_BLOCKS:
		slots.append(Blocks.id_of(block_name))
	_refresh()


func _process(_delta: float) -> void:
	var age := Time.get_ticks_msec() / 1000.0 - _name_shown_at
	_name_label.modulate.a = clampf(1.0 - (age - NAME_SECONDS) / NAME_FADE, 0.0, 1.0)


func selected_block() -> int:
	return slots[selected]


func select(slot: int) -> void:
	selected = posmod(slot, SLOT_COUNT)
	_refresh()
	_show_name()
	selection_changed.emit(selected)


## Wheel: +1 next slot, -1 previous (wraps around like the classic game).
func scroll(direction: int) -> void:
	select(selected + direction)


func set_slot(slot: int, block_id: int) -> void:
	slots[slot] = block_id
	_refresh()
	if slot == selected:
		_show_name()


## Puts a block in the hotbar like picking it in creative mode: selects the
## slot that already has it, otherwise replaces the selected slot.
func pick(block_id: int) -> void:
	var existing := slots.find(block_id)
	if existing >= 0:
		select(existing)
	else:
		set_slot(selected, block_id)


static func display_name(block_id: int) -> String:
	return Blocks.get_type(block_id).name.capitalize()


func _refresh() -> void:
	for i in SLOT_COUNT:
		_icons[i].texture = BlockIcons.get_icon(slots[i]) if slots[i] != Blocks.AIR else null
	_selector.position = Vector2(-1 + selected * 20, -1) * P


func _show_name() -> void:
	_name_label.text = display_name(slots[selected])
	_name_shown_at = Time.get_ticks_msec() / 1000.0
