class_name FreeCamera
extends Camera3D
## Free "flying" camera.
## LMB: capture the mouse, Esc - release it.
## WASD: movement, E/Space - up, Q - down, Shift - speed boost,
## mouse wheel: change the base speed.

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
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				move_speed = clampf(move_speed * 1.1, min_speed, max_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				move_speed = clampf(move_speed / 1.1, min_speed, max_speed)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -PI / 2 + 0.01, PI / 2 - 0.01)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var vertical := Input.get_axis("move_down", "move_up")

	var direction := global_basis.x * input.x + global_basis.z * input.y + Vector3.UP * vertical
	if direction.is_zero_approx():
		return

	var speed := move_speed * (sprint_multiplier if Input.is_action_pressed("sprint") else 1.0)
	global_position += direction.normalized() * speed * delta
