class_name AchievementToast
extends Control
## "Achievement get!" like the classic game: a plate with the
## achievement's icon and name slides down at the top right, stays a few
## seconds and slides back up. Several queue up. The plate is drawn in
## pixels like the modern game's toasts: a black edge with rounded corners,
## a grey frame 2 pixels wide, dark grey inside.

const P := UiTheme.PIXEL
const WIDTH := 160 * P
const HEIGHT := 32 * P
const SHOW_SECONDS := 3.0
const SLIDE_SECONDS := 0.4

var _queue: Array[String] = []
var _time := -1.0
var _plate: Control
var _icon: ItemSlotView
var _title: Label
var _name: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # finishes sliding while the game is paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate = Control.new()
	_plate.draw.connect(_draw_plate)
	_plate.size = Vector2(WIDTH, HEIGHT)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	_icon = ItemSlotView.new()
	_icon.position = Vector2(8, 8) * P
	_plate.add_child(_icon)
	_title = _label(Color("ffff00"), Vector2(30, 6))
	_name = _label(Color.WHITE, Vector2(30, 17))
	_plate.visible = false
	Stats.on_achievement = show_achievement


func _exit_tree() -> void:
	if Stats.on_achievement == Callable(self, "show_achievement"):
		Stats.on_achievement = Callable()


const EDGE := Color8(0, 0, 0)
const FRAME := Color8(96, 96, 96)
const INSIDE := Color8(36, 36, 36)


func _draw_plate() -> void:
	_rounded(0, 1, EDGE)
	_rounded(1, 1, FRAME)
	_rounded(3, 1, INSIDE)


## A rectangle `inset` pixels in from the plate's edge with `corner`
## pixels cut off each corner (in UiTheme pixels).
func _rounded(inset: int, corner: int, color: Color) -> void:
	var w := WIDTH / P - inset * 2
	var h := HEIGHT / P - inset * 2
	_plate.draw_rect(Rect2(Vector2(inset + corner, inset) * P, Vector2(w - corner * 2, h) * P), color)
	_plate.draw_rect(Rect2(Vector2(inset, inset + corner) * P, Vector2(w, h - corner * 2) * P), color)


func _label(color: Color, at: Vector2) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UiTheme.font())
	label.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", UiTheme.SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", P)
	label.add_theme_constant_override("shadow_offset_y", P)
	label.position = at * P
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(label)
	return label


func show_achievement(id: String) -> void:
	_queue.append(id)


func _process(delta: float) -> void:
	if _time < 0.0:
		if _queue.is_empty():
			_plate.visible = false
			return
		var id: String = _queue.pop_front()
		var info: Array = Stats.ACHIEVEMENTS[id]
		_icon.set_item(Items.id_of(info[3]), 1, false)
		_title.text = Lang.t("Achievement get!")
		_name.text = Lang.t(info[0])
		_time = 0.0
		_plate.visible = true
	_time += delta
	var total := SHOW_SECONDS + SLIDE_SECONDS * 2.0
	var shown := clampf(minf(_time, total - _time) / SLIDE_SECONDS, 0.0, 1.0)
	_plate.position = Vector2(size.x - WIDTH, lerpf(-HEIGHT, 0.0, shown))
	if _time >= total:
		_time = -1.0
