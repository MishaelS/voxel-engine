class_name Menu
extends Control
## In-game menu. Esc opens it (the game pauses: ticks stop), Esc again or
## "Done" goes back one screen; leaving the last screen resumes the game.
## Screens are MenuScreen nodes kept on a stack.

## World and player for screens that act on them (World Settings).
@export var world: VoxelWorld
@export var chat: Chat
## In game: opening a screen pauses the game and Esc opens the Game Menu.
## On the title screen both are off.
@export var in_game := true

## The first screen was opened / the last screen was closed.
signal opened
signal closed

var _stack: Array[MenuScreen] = []
var _blur: Control
var _dim: ColorRect
var _dirt: Control
var _dirt_list: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.theme()
	# The game behind the menu is slightly blurred and dimmed.
	_blur = UiTheme.blur_rect()
	_blur.visible = false
	add_child(_blur)
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.06, 0.08, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)
	_dirt = _make_dirt_background()
	add_child(_dirt)


## The classic options background, used on the title screen: dark tiled
## dirt, the list area darker still with soft shadows at its edges.
func _make_dirt_background() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	var texture := UiTheme.background_texture()
	var back := TextureRect.new()
	back.texture = texture
	back.stretch_mode = TextureRect.STRETCH_TILE
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.modulate = Color(0.25, 0.25, 0.25)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)
	_dirt_list = Control.new()
	_dirt_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dirt_list.clip_contents = true
	root.add_child(_dirt_list)
	var band := TextureRect.new()
	band.texture = texture
	band.stretch_mode = TextureRect.STRETCH_TILE
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.modulate = Color(0.125, 0.125, 0.125)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dirt_list.add_child(band)
	# Shadows cast by the header and footer onto the list.
	for top in [true, false]:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0, 0, 0, 0.9) if top else Color(0, 0, 0, 0))
		gradient.set_color(1, Color(0, 0, 0, 0) if top else Color(0, 0, 0, 0.9))
		var shade_texture := GradientTexture2D.new()
		shade_texture.gradient = gradient
		shade_texture.fill_to = Vector2(0, 1)
		var shade := TextureRect.new()
		shade.texture = shade_texture
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.anchor_right = 1.0
		shade.anchor_top = 0.0 if top else 1.0
		shade.anchor_bottom = 0.0 if top else 1.0
		shade.offset_top = 0 if top else -4 * UiTheme.PIXEL
		shade.offset_bottom = 4 * UiTheme.PIXEL if top else 0
		_dirt_list.add_child(shade)
	return root


func _process(_delta: float) -> void:
	_dirt.visible = not in_game and is_open()
	if _dirt.visible:
		# The darker band follows the current screen's list area.
		var area := _stack[-1].list_area
		if area and area.is_inside_tree():
			var rect := area.get_global_rect()
			_dirt_list.global_position = Vector2(0, rect.position.y - 4 * UiTheme.PIXEL)
			_dirt_list.size = Vector2(size.x, rect.size.y + 8 * UiTheme.PIXEL)


func is_open() -> bool:
	return not _stack.is_empty()


func open_pause_menu() -> void:
	push(PauseScreen.new())


func push(screen: MenuScreen) -> void:
	if _stack.is_empty():
		if in_game:
			get_tree().paused = true
			GameInput.lock()
			_dim.visible = true
			_blur.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		opened.emit()
	else:
		_stack[-1].visible = false
	screen.menu = self
	_stack.append(screen)
	add_child(screen)


## Shows `screen` in place of the current one (switching pages).
func replace(screen: MenuScreen) -> void:
	if not _stack.is_empty():
		_stack.pop_back().queue_free()
	screen.menu = self
	_stack.append(screen)
	add_child(screen)


## Closes the current screen; closing the last one resumes the game.
func back() -> void:
	if _stack.is_empty():
		return
	_stack.pop_back().queue_free()
	if _stack.is_empty():
		if in_game:
			_dim.visible = false
			_blur.visible = false
			get_tree().paused = false
			GameInput.unlock()
		closed.emit()
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
	elif in_game and (chat == null or not chat.is_open()):
		open_pause_menu()
	get_viewport().set_input_as_handled()
