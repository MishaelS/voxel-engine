class_name ItemSlotView
extends Control
## One item stack drawn like the classic game: the icon (16x16 texture
## pixels; blocks as small 3D cubes, items flat), for more than one item
## the count in the bottom right corner, and for worn tools the durability
## bar. Used by the hotbar, inventory screens and the stack held by the
## mouse.

const P := UiTheme.PIXEL
const SIZE := 16 * P

var id := Blocks.AIR
var count := 0

var damage := 0

var _icon: TextureRect
var _count: Label
var _bar_back: ColorRect
var _bar: ColorRect
## Drawn while the slot is empty (the armor slots' outlines of a helmet,
## chestplate, leggings and boots, like Beta's).
var empty_icon: Texture2D:
	set(value):
		empty_icon = value
		refresh()


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
	# The classic durability bar: 13 pixels at the bottom, green to red.
	_bar_back = ColorRect.new()
	_bar_back.color = Color.BLACK
	_bar_back.position = Vector2(2, 13) * P
	_bar_back.size = Vector2(13, 2) * P
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.visible = false
	add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.position = Vector2(2, 13) * P
	_bar.size = Vector2(12, 1) * P
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.visible = false
	add_child(_bar)


func set_item(item_id: int, item_count: int, show_count: bool = true, item_damage: int = 0) -> void:
	if item_count <= 0:
		item_id = Blocks.AIR
	id = item_id
	count = item_count
	damage = item_damage
	_icon.texture = _texture_for(item_id)
	_count.text = str(item_count) if show_count and item_count > 1 and item_id != Blocks.AIR else ""
	var durability := Items.durability(item_id)
	var worn := durability > 0 and item_damage > 0
	_bar_back.visible = worn
	_bar.visible = worn
	if worn:
		var left := 1.0 - float(item_damage) / durability
		_bar.size.x = roundf(13.0 * left) * P
		_bar.color = Color.from_hsv(left / 3.0, 1.0, 1.0)


## Re-fetches the icon (after the GUI scale changed).
func refresh() -> void:
	_icon.texture = _texture_for(id)


func _texture_for(item_id: int) -> Texture2D:
	if item_id == Blocks.AIR and empty_icon:
		return empty_icon
	return BlockIcons.get_icon(item_id)
