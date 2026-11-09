class_name IsometricCamera
extends Camera3D
## The isometric camera (F6), like the old game's isometric view: an
## orthographic camera looking down at the player from a fixed angle,
## facing one of the four diagonals. Z / X turn it by 90 degrees, the mouse
## wheel zooms. Angle, facing and zoom are Isometric Camera settings.

## View angles below the horizon (Classic, True Isometric, Steep).
const ANGLES: Array[float] = [30.0, 35.264, 45.0]
const DISTANCE := 600.0

var target: Node3D

var _size := 64.0


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	near = 1.0
	far = 2000.0
	_size = Settings.get_value("iso_zoom")


## Rotation for a facing (0..3, the diagonals) and an angle setting index.
static func view_basis(facing: int, angle_index: int) -> Basis:
	var yaw := deg_to_rad(45.0 + 90.0 * facing)
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -deg_to_rad(ANGLES[angle_index]))


func _process(delta: float) -> void:
	if not current or target == null:
		return
	# Smooth zoom toward the setting.
	_size = lerpf(_size, Settings.get_value("iso_zoom"), minf(delta * 10.0, 1.0))
	size = _size
	basis = view_basis(Settings.get_value("iso_facing"), Settings.get_value("iso_angle"))
	global_position = target.global_position + Vector3(0, 1.0, 0) + basis.z * DISTANCE


func rotate_view(step: int) -> void:
	Settings.set_value("iso_facing", posmod(int(Settings.get_value("iso_facing")) + step, 4))


func zoom(step: int) -> void:
	var zoom_setting := Settings.get_setting("iso_zoom")
	Settings.set_value("iso_zoom", float(Settings.get_value("iso_zoom")) + step * zoom_setting.step)
