class_name DeathScreen
extends Control
## "You died!" like the classic game: the view falls over, the screen turns
## red, then Respawn and Title Screen appear. Respawning puts the player
## back at the world spawn with full health and food.

const P := UiTheme.PIXEL

@export var player: Player
@export var world: VoxelWorld

var _buttons: VBoxContainer
var _shown_at := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.31, 0.0, 0.0, 0.38))
	gradient.set_color(1, Color(0.5, 0.19, 0.19, 0.63))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

	var title := Label.new()
	title.text = "You died!"
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE * 2)
	title.add_theme_constant_override("shadow_offset_x", 2 * P)
	title.add_theme_constant_override("shadow_offset_y", 2 * P)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -150 * P
	title.offset_right = 150 * P
	title.offset_top = 60 * P
	add_child(title)

	var score := Label.new()
	score.text = "Score: 0"
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score.offset_left = -150 * P
	score.offset_right = 150 * P
	score.offset_top = 100 * P
	add_child(score)

	_buttons = VBoxContainer.new()
	_buttons.set_anchors_preset(Control.PRESET_CENTER)
	_buttons.offset_left = -UiTheme.WIDE_BUTTON / 2.0
	_buttons.offset_right = UiTheme.WIDE_BUTTON / 2.0
	_buttons.add_theme_constant_override("separation", 4 * P)
	add_child(_buttons)
	_buttons.add_child(_button("Respawn", _respawn))
	_buttons.add_child(_button("Title Screen", func() -> void:
		_respawn()
		var game := Game.find(get_tree())
		if game:
			game.quit_to_title()))

	if player:
		player.died.connect(_show)


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(UiTheme.WIDE_BUTTON, UiTheme.BUTTON_HEIGHT)
	button.pressed.connect(on_pressed)
	return button


func _show() -> void:
	visible = true
	_shown_at = Time.get_ticks_msec() / 1000.0
	GameInput.lock()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Like the classic game the buttons appear after a moment.
	_buttons.visible = false
	get_tree().create_timer(1.0).timeout.connect(func() -> void: _buttons.visible = true)


func _respawn() -> void:
	if not visible:
		return
	visible = false
	GameInput.unlock()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.respawn(world.find_spawn() if world else Vector3.ZERO)
