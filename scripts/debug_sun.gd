extends DirectionalLight3D
## Debug control of the sun direction to inspect shadows from any angle.
## Left/Right arrows - rotate around the vertical axis,
## Up/Down arrows - change elevation (sun height above the horizon).

@export var rotate_speed_deg: float = 60.0
@export var min_elevation_deg: float = 5.0
@export var max_elevation_deg: float = 89.0

var _yaw := 0.0
var _elevation := 0.0


func _ready() -> void:
	# Light shines along -Z: elevation is how far that direction points down.
	_yaw = rotation.y
	_elevation = -rotation.x


func _process(delta: float) -> void:
	var yaw_input := Input.get_axis("sun_rotate_left", "sun_rotate_right")
	var pitch_input := Input.get_axis("sun_lower", "sun_raise")
	if yaw_input == 0.0 and pitch_input == 0.0:
		return
	var step := deg_to_rad(rotate_speed_deg) * delta
	_yaw -= yaw_input * step
	_elevation = clampf(_elevation + pitch_input * step, deg_to_rad(min_elevation_deg), deg_to_rad(max_elevation_deg))
	rotation = Vector3(-_elevation, _yaw, 0.0)


## Elevation and yaw in degrees, for the HUD.
func describe() -> String:
	return "elevation %.0f°, yaw %.0f°" % [rad_to_deg(_elevation), wrapf(rad_to_deg(_yaw), 0.0, 360.0)]
