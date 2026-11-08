class_name ItemSlotView
extends Control
## One item stack drawn like the classic game: the block icon (16x16
## texture pixels) and, for more than one item, the count in the bottom
## right corner. Used by the hotbar, inventory screens and the stack held
## by the mouse.

const P := UiTheme.PIXEL
const SIZE := 16 * P

var id := Blocks.AIR
var count := 0

var _icon: TextureRect
var _count: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	_icon = TextureRect.new()
	_icon.size = Vector2(SIZE, SIZE)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# The classic position: right edge 1 pixel past the slot, digits
	# standing on the slot's bottom edge (baseline at 16 pixels).
	var ascent := UiTheme.font().get_ascent(UiTheme.FONT_SIZE)
	_count.position = Vector2(17 * P - SIZE * 2, 16 * P - ascent)
	_count.size = Vector2(SIZE * 2, SIZE)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.theme = UiTheme.theme()
	_count.add_theme_color_override("font_color", Color.WHITE)
	add_child(_count)


func set_item(item_id: int, item_count: int, show_count: bool = true) -> void:
	if item_count <= 0:
		item_id = Blocks.AIR
	id = item_id
	count = item_count
	_icon.texture = BlockIcons.get_icon(item_id)
	_count.text = str(item_count) if show_count and item_count > 1 and item_id != Blocks.AIR else ""


## Re-fetches the icon (after the GUI scale changed).
func refresh() -> void:
	_icon.texture = BlockIcons.get_icon(id)
