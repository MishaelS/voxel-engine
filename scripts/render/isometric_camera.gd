class_name IsometricCamera
extends Camera3D
## The World Diorama's camera (F6): an orthographic camera looking down at
## the area around the player from far away. Rotation, Tilt and Zoom are
## settings (the diorama's controls change them); `pan` moves it off the
## player (drag), Center Camera brings it back.

const DISTANCE := 600.0

var target: Node3D
## Offset of the view's center from the player (blocks, on the ground).
var pan := Vector3.ZERO

var _size := 96.0


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	near = 1.0
	far = 2000.0
	_size = Settings.get_value("iso_zoom")


## Rotation for a yaw (degrees around the area, 45 = the classic north-east
## diagonal) and a tilt (degrees below the horizon).
static func view_basis(yaw_degrees: float, tilt_degrees: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Basis(Vector3.RIGHT, -deg_to_rad(tilt_degrees))


## The view's rotation from the settings.
static func settings_basis() -> Basis:
	return view_basis(Settings.get_value("iso_rotation"), Settings.get_value("iso_tilt"))


func _process(delta: float) -> void:
	if not current or target == null:
		return
	# Smooth zoom toward the setting.
	_size = lerpf(_size, Settings.get_value("iso_zoom"), minf(delta * 10.0, 1.0))
	size = _size
	basis = settings_basis()
	global_position = center() + basis.z * DISTANCE


## The point the camera looks at.
func center() -> Vector3:
	return target.global_position + Vector3(0, 1.0, 0) + pan


## Turns the view by degrees (the < > buttons: 90, dragging: a little).
func rotate_view(degrees: float) -> void:
	Settings.set_value("iso_rotation", fposmod(float(Settings.get_value("iso_rotation")) + degrees, 360.0))


func zoom(step: int) -> void:
	# Bigger steps when far out (a step is about an eighth of the view).
	var now: float = Settings.get_value("iso_zoom")
	var step_size := Settings.get_setting("iso_zoom").step * maxf(1.0, roundf(now / 64.0))
	Settings.set_value("iso_zoom", now + step * step_size)


## Moves the view by a mouse drag of `pixels` on a screen `screen_height`
## pixels tall: the ground under the mouse follows it.
func drag(pixels: Vector2, screen_height: float) -> void:
	var per_pixel := size / maxf(screen_height, 1.0)
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var forward := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var tilt := deg_to_rad(float(Settings.get_value("iso_tilt")))
	pan -= right * pixels.x * per_pixel
	pan += forward * pixels.y * per_pixel / maxf(sin(tilt), 0.2)
