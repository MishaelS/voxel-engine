class_name SignEditScreen
extends Control
## "Edit sign message", like the classic game: right after placing a sign
## its 4 lines (up to 15 letters each) are typed in; Enter moves to the
## next line, Done (or Esc) keeps the text.

var world: VoxelWorld
var pos := Vector3i.ZERO
var _lines: Array[LineEdit] = []


func _init(target_world: VoxelWorld, sign_pos: Vector3i) -> void:
	world = target_world
	pos = sign_pos


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	add_child(UiTheme.blur_rect())
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.06, 0.08, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 4 * UiTheme.PIXEL)
	box.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, 0)
	box.position = Vector2(-UiTheme.WIDE_BUTTON / 2.0, -80 * UiTheme.PIXEL)
	add_child(box)
	var title := Label.new()
	title.text = "Edit sign message:"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for i in SignBehavior.LINES:
		var line := LineEdit.new()
		line.max_length = SignBehavior.LINE_LENGTH
		line.alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
		line.text_submitted.connect(func(_text: String) -> void: _next_line(i))
		box.add_child(line)
		_lines.append(line)
	var done := Button.new()
	done.text = "Done"
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	done.pressed.connect(_finish)
	box.add_child(done)
	GameInput.lock()
	GameInput.capture(false)
	_lines[0].grab_focus.call_deferred()


func _next_line(i: int) -> void:
	if i + 1 < _lines.size():
		_lines[i + 1].grab_focus()
	else:
		_finish()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_finish()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	var text := []
	for line in _lines:
		text.append(line.text)
	world.set_sign_text(pos, text)
	GameInput.unlock()
	GameInput.capture(true)
	queue_free()
