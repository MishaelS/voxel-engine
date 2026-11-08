class_name FreeCamera
extends Camera3D
## Free "flying" camera.
## LMB: capture the mouse (Esc opens the menu, which releases it).
## Ctrl + mouse wheel: change the fly speed.
## WASD: movement, E/Space - up, Q - down, Shift - speed boost,

@export var move_speed: float = 5.0
@export var sprint_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.002
@export var min_speed: float = 0.5
@export var max_speed: float = 100.0

var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if GameInput.is_blocked():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					get_viewport().set_input_as_handled() # this click only captures
			MOUSE_BUTTON_WHEEL_UP:
				if event.ctrl_pressed: # plain wheel = hotbar
					move_speed = clampf(move_speed * 1.1, min_speed, max_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.ctrl_pressed:
					move_speed = clampf(move_speed / 1.1, min_speed, max_speed)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = mouse_sensitivity * Settings.get_value("mouse_sensitivity") / 100.0
		var invert := -1.0 if Settings.get_value("invert_mouse") else 1.0
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity * invert, -PI / 2 + 0.01, PI / 2 - 0.01)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if GameInput.is_blocked():
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var vertical := Input.get_axis("move_down", "move_up")

	var direction := global_basis.x * input.x + global_basis.z * input.y + Vector3.UP * vertical
	if direction.is_zero_approx():
		return

	var speed := move_speed * (sprint_multiplier if Input.is_action_pressed("sprint") else 1.0)
	global_position += direction.normalized() * speed * delta
