class_name DayNightCycle
extends DirectionalLight3D
## Moves the sun along its daily path, counts days and drives the sky shader.
## During the day this light is the sunlight; at night it becomes the
## moonlight (opposite the sun, dim and bluish, brighter near full moon).
##
## Time of day is an angle on the sun's path:
## 0° = sunrise, 90° = noon, 180° = sunset, 270° = midnight.
## A new day starts at sunrise. The moon goes through its phases over
## lunar_cycle_days days.
## Up/Down arrows - change time of day, Left/Right - rotate the sun path,
## T - toggle the automatic day cycle, M - skip to the next day.

const PHASE_NAMES: Array[String] = [
	"new moon", "waxing crescent", "first quarter", "waxing gibbous",
	"full moon", "waning gibbous", "last quarter", "waning crescent",
]

@export var world_environment: WorldEnvironment

@export_group("Path")
@export_range(0.0, 360.0) var time_of_day_deg: float = 50.0
## Direction of the sun path around the vertical axis.
@export_range(-180.0, 180.0) var path_yaw_deg: float = 35.0
## Tilt of the path so the noon sun is not straight overhead (readable shadows).
@export_range(0.0, 60.0) var path_tilt_deg: float = 25.0

@export_group("Cycle")
@export var auto_cycle: bool = false
## Real seconds per full day (like 20 minutes in the classic game).
@export var day_length_sec: float = 1200.0
## Degrees per second when changing time / path with the arrow keys.
@export var manual_speed_deg: float = 45.0
## Current day number (day 0 starts at full moon).
@export var day: int = 0
## Days for a full cycle of moon phases (29.5 in reality).
@export var lunar_cycle_days: float = 8.0

@export_group("Light")
@export var sun_energy: float = 1.2
## Moonlight at full moon; scales down with the lit part of the moon.
@export var moon_energy: float = 0.25
@export var sun_color: Color = Color(1.0, 0.96, 0.9)
@export var low_sun_color: Color = Color(1.0, 0.6, 0.35)
@export var moon_color: Color = Color(0.6, 0.7, 1.0)

var _sky_material: ShaderMaterial


func _ready() -> void:
	if world_environment and world_environment.environment and world_environment.environment.sky:
		_sky_material = world_environment.environment.sky.sky_material as ShaderMaterial
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_day_cycle"):
		auto_cycle = not auto_cycle
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("next_day"):
		day += 1
		_apply()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var time_input := Input.get_axis("sun_lower", "sun_raise")
	var yaw_input := Input.get_axis("sun_rotate_left", "sun_rotate_right")
	if not auto_cycle and time_input == 0.0 and yaw_input == 0.0:
		return
	var step := time_input * manual_speed_deg * delta
	if auto_cycle:
		step += 360.0 * delta / day_length_sec
	advance_time(step)
	path_yaw_deg = wrapf(path_yaw_deg - yaw_input * manual_speed_deg * delta, -180.0, 180.0)
	_apply()


## Moves the clock by degrees (can be negative), counting days at sunrise.
func advance_time(degrees: float) -> void:
	var total := time_of_day_deg + degrees
	day += floori(total / 360.0)
	time_of_day_deg = fposmod(total, 360.0)


## Unit vector pointing toward the sun.
func sun_direction() -> Vector3:
	var angle := deg_to_rad(time_of_day_deg)
	var direction := Vector3(cos(angle), sin(angle), 0.0)
	direction = direction.rotated(Vector3.RIGHT, deg_to_rad(path_tilt_deg))
	return direction.rotated(Vector3.UP, deg_to_rad(path_yaw_deg)).normalized()


## Moon phase 0..1: 0 = new moon, 0.25 = first quarter, 0.5 = full,
## 0.75 = last quarter. Changes smoothly through the day.
func moon_phase() -> float:
	var days := day + time_of_day_deg / 360.0
	return fposmod(0.5 + days / lunar_cycle_days, 1.0)


## Lit part of the moon disc: 0 = new moon, 1 = full moon.
func moon_illumination() -> float:
	return 0.5 - 0.5 * cos(moon_phase() * TAU)


func moon_phase_name() -> String:
	return PHASE_NAMES[roundi(moon_phase() * 8.0) % 8]


func _apply() -> void:
	var to_sun := sun_direction()
	var is_day := to_sun.y >= 0.0
	var to_light := to_sun if is_day else -to_sun
	# A DirectionalLight3D shines along its -Z axis.
	global_basis = Basis.looking_at(-to_light, Vector3.UP)

	# Light fades out near the horizon (dawn/dusk) before switching sun <-> moon.
	var fade := smoothstep(0.0, 0.12, to_light.y)
	if is_day:
		light_color = low_sun_color.lerp(sun_color, smoothstep(0.0, 0.35, to_light.y))
		light_energy = sun_energy * fade
	else:
		light_color = moon_color
		light_energy = moon_energy * fade * (0.15 + 0.85 * moon_illumination())

	if _sky_material:
		_sky_material.set_shader_parameter("sun_direction", to_sun)
		_sky_material.set_shader_parameter("moon_phase", moon_phase())


## Day, clock time (sunrise = 06:00) and moon phase for the HUD.
func describe() -> String:
	var hours := wrapf(6.0 + time_of_day_deg / 15.0, 0.0, 24.0)
	return "day %d, %02d:%02d%s, %s (%d%%)" % [
		day, int(hours), int(fmod(hours, 1.0) * 60.0), " (auto)" if auto_cycle else "",
		moon_phase_name(), roundi(moon_illumination() * 100.0),
	]
