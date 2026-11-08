class_name Menu
extends Control
## In-game menu. Esc opens it (the game pauses: ticks stop), Esc again or
## "Done" goes back one screen; leaving the last screen resumes the game.
## Screens are MenuScreen nodes kept on a stack.

## World and player for screens that act on them (World Settings).
@export var world: VoxelWorld
@export var chat: Chat

var _stack: Array[MenuScreen] = []
var _dim: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.theme()
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.06, 0.08, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)


func is_open() -> bool:
	return not _stack.is_empty()


func open_pause_menu() -> void:
	push(PauseScreen.new())


func push(screen: MenuScreen) -> void:
	if _stack.is_empty():
		get_tree().paused = true
		GameInput.lock()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_dim.visible = true
	else:
		_stack[-1].visible = false
	screen.menu = self
	_stack.append(screen)
	add_child(screen)


## Closes the current screen; closing the last one resumes the game.
func back() -> void:
	if _stack.is_empty():
		return
	_stack.pop_back().queue_free()
	if _stack.is_empty():
		_dim.visible = false
		get_tree().paused = false
		GameInput.unlock()
	else:
		_stack[-1].visible = true
		_stack[-1].refresh()


func close() -> void:
	while is_open():
		back()


func _input(event: InputEvent) -> void:
	# A screen waiting for a key (rebinding) gets keys before anything else.
	if is_open() and event is InputEventKey and event.pressed and not event.echo:
		if _stack[-1].capture_key(event):
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_open():
		back()
	elif chat == null or not chat.is_open():
		open_pause_menu()
	get_viewport().set_input_as_handled()
