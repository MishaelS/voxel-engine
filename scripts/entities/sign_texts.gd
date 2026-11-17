class_name SignTexts
extends Node3D
## Draws the text of signs (their block entities) as Label3D nodes on the
## boards' fronts, black like the game's, sized like Beta 1.7.3's
## TileEntitySignRenderer: a font pixel 1/90 block (15 letters fill the
## board's width), a line every 10 of them, centered.

const FONT_SIZE := 32 # (4 units a font pixel: UiTheme's font is 8 pixels at 16)
const PIXEL_SIZE := 1.0 / 90.0 / 4.0
const LINE_PIXELS := 10

var world: VoxelWorld
var _labels := {} # Vector3i -> Label3D


## Shows (or updates) the text of the sign at `pos`.
func update(pos: Vector3i, lines: Array) -> void:
	var id := world.get_block(pos)
	if not SignBehavior.is_sign(id):
		remove(pos)
		return
	var label: Label3D = _labels.get(pos)
	if label == null:
		label = Label3D.new()
		label.font = UiTheme.font()
		label.font_size = FONT_SIZE
		label.pixel_size = PIXEL_SIZE
		label.modulate = Color.BLACK
		label.outline_size = 0
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.line_spacing = LINE_PIXELS * 4 - label.font.get_height(FONT_SIZE)
		add_child(label)
		_labels[pos] = label
	var place := SignBehavior.text_place(id)
	label.position = Vector3(pos) + place[0]
	label.rotation = Vector3(0, place[1], 0)
	label.text = "\n".join(PackedStringArray(lines))


## Every second: signs whose ground has loaded get their text.
var _wait := 0.0


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 1.0
	var signs := world.sign_entities()
	for pos: Vector3i in signs:
		if not _labels.has(pos) and world.is_inside(pos) and SignBehavior.is_sign(world.get_block(pos)):
			update(pos, signs[pos].lines)


func remove(pos: Vector3i) -> void:
	var label: Label3D = _labels.get(pos)
	if label:
		label.queue_free()
		_labels.erase(pos)


func clear() -> void:
	for label: Label3D in _labels.values():
		label.queue_free()
	_labels.clear()
