class_name DayNightCycle
extends DirectionalLight3D
## Moves the sun along its daily path, counts days and drives the sky shader.
## During the day this light is the sunlight; at night it becomes the
## moonlight (opposite the sun, dim and bluish, brighter near full moon).
##
## Time comes from the world clock (game ticks, 24000 per day; see
## WorldClock), interpolated between ticks so the sun moves smoothly.
## Here it is used as an angle (mean solar time):
## 0° = 06:00, 90° = 12:00, 180° = 18:00, 270° = 00:00.
## A new day starts at 06:00. The moon goes through its phases over
## lunar_cycle_days days.
##
## The sun position is computed astronomically for an observer at
## latitude_deg. With the analemma enabled the sun also follows the year:
## - declination (axial tilt): higher and longer days in summer, lower and
##   shorter in winter;
## - equation of time (orbit eccentricity + tilt): the sun runs up to
##   ~16 minutes ahead of / behind the clock.
## Photographed at the same clock time every day, the sun traces a figure 8
## (the analemma) over year_length_days.
##
## Up/Down arrows - change time of day, Left/Right - rotate the sun path,
## T - toggle the daylight cycle (time stops), M - skip to the next day.

const PHASE_NAMES: Array[String] = [
	"new moon", "waxing crescent", "first quarter", "waxing gibbous",
	"full moon", "waning gibbous", "last quarter", "waning crescent",
]

@export var world_environment: WorldEnvironment
## World whose clock sets the time. Without it the time is only changed
## through time_of_day_deg / day (useful for tests).
@export var world: VoxelWorld

## Time of day as an angle (0° = 06:00) and day number; taken from the
## world clock every frame.
var time_of_day_deg: float = 50.0
var day: int = 0

@export_group("Path")
## Direction of the sun path around the vertical axis.
@export_range(-180.0, 180.0) var path_yaw_deg: float = 35.0
## Observer latitude. 0 = equator (sun passes overhead at equinox noon),
## positive = northern hemisphere (sun stays in the south, readable shadows).
@export_range(-80.0, 80.0) var latitude_deg: float = 25.0

@export_group("Year")
## Seasons and the equation of time (the analemma). Off = every day is an equinox.
@export var analemma_enabled: bool = true
@export var year_length_days: float = 365.2422
## Day of the year on game day 0 (0 = January 1, 79 = March 20 equinox).
@export var start_day_of_year: float = 79.0
## Earth's axial tilt: how far the sun moves north/south over the year.
@export_range(0.0, 45.0) var axial_tilt_deg: float = 23.44
## Earth's orbit eccentricity: the sun's uneven speed over the year.
@export_range(0.0, 0.3) var orbit_eccentricity: float = 0.0167
## Day of the year of the perihelion (closest to the sun, ~January 3).
@export var perihelion_day_of_year: float = 2.0

@export_group("Cycle")
## Degrees per second when changing time / path with the arrow keys.
@export var manual_speed_deg: float = 45.0
## Days for a full cycle of moon phases (29.5 in reality). Day 0 is full moon.
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
	if world == null:
		return
	if event.is_action_pressed("toggle_day_cycle"):
		world.clock.daylight_cycle = not world.clock.daylight_cycle
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("next_day"):
		world.clock.add_day_time(WorldClock.TICKS_PER_DAY)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var time_input := Input.get_axis("sun_lower", "sun_raise")
	var yaw_input := Input.get_axis("sun_rotate_left", "sun_rotate_right")
	path_yaw_deg = wrapf(path_yaw_deg - yaw_input * manual_speed_deg * delta, -180.0, 180.0)
	if world:
		if time_input != 0.0:
			world.clock.add_day_time(time_input * manual_speed_deg * delta / 360.0 * WorldClock.TICKS_PER_DAY)
		_sync_with_clock()
	_apply()


## Takes the time from the world clock, interpolated between game ticks.
func _sync_with_clock() -> void:
	var clock := world.clock
	var day_time := clock.day_time
	if clock.daylight_cycle and not TickLoop.frozen:
		day_time += TickLoop.alpha
	day = floori(day_time / WorldClock.TICKS_PER_DAY)
	time_of_day_deg = fposmod(day_time, WorldClock.TICKS_PER_DAY) / WorldClock.TICKS_PER_DAY * 360.0


## Unit vector pointing toward the sun (+X east, +Y up, -Z north before
## path_yaw_deg is applied).
func sun_direction() -> Vector3:
	# Hour angle: 0 at true solar noon. The clock gives mean solar time;
	# the equation of time shifts the real sun ahead of / behind it.
	var hour_angle := deg_to_rad(time_of_day_deg - 90.0)
	var declination := 0.0
	if analemma_enabled:
		hour_angle += equation_of_time_rad()
		declination = declination_rad()
	var latitude := deg_to_rad(latitude_deg)

	# Horizontal coordinates of the sun for an observer at this latitude.
	var up := sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hour_angle)
	var east := -cos(declination) * sin(hour_angle)
	var north := cos(latitude) * sin(declination) - sin(latitude) * cos(declination) * cos(hour_angle)
	var direction := Vector3(east, up, -north)
	return direction.rotated(Vector3.UP, deg_to_rad(path_yaw_deg)).normalized()


## Fractional day of the year (0 = January 1), advancing with the clock.
func day_of_year() -> float:
	return fposmod(start_day_of_year + day + time_of_day_deg / 360.0, year_length_days)


## Sun's mean anomaly: its position on the orbit counted from the perihelion.
func _mean_anomaly() -> float:
	return TAU * (day_of_year() - perihelion_day_of_year) / year_length_days


## Longitude of the perihelion measured from the March equinox (282.94°).
const PERIHELION_LONGITUDE := deg_to_rad(282.94)


## Sun's declination: its angle north (+) or south (-) of the celestial
## equator. Gives the seasons: +tilt at the June solstice, -tilt in December.
func declination_rad() -> float:
	var anomaly := _mean_anomaly()
	var ecliptic_longitude := anomaly + 2.0 * orbit_eccentricity * sin(anomaly) + PERIHELION_LONGITUDE
	return asin(sin(deg_to_rad(axial_tilt_deg)) * sin(ecliptic_longitude))


## Equation of time as an angle of Earth's rotation (apparent - mean solar
## time; 0.0044 rad = 1 minute). Sum of the eccentricity effect and the
## axial tilt effect; about -14 to +16 minutes for Earth.
func equation_of_time_rad() -> float:
	var anomaly := _mean_anomaly()
	var tilt_term := pow(tan(deg_to_rad(axial_tilt_deg) * 0.5), 2.0)
	return -2.0 * orbit_eccentricity * sin(anomaly) + tilt_term * sin(2.0 * (anomaly + PERIHELION_LONGITUDE))


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
	# A DirectionalLight3D shines along its -Z axis. Near the zenith "up"
	# would be parallel to the light, so use another reference axis.
	var reference_up := Vector3.UP if absf(to_light.y) < 0.999 else Vector3.FORWARD
	global_basis = Basis.looking_at(-to_light, reference_up)

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


## Calendar date for an Earth-like year, e.g. "Mar 21".
func date_string() -> String:
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	const LENGTHS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	# Scale to a 365-day calendar so any year length maps onto 12 months.
	var remaining := int(day_of_year() * 365.0 / year_length_days)
	for month in 12:
		if remaining < LENGTHS[month]:
			return "%s %d" % [MONTHS[month], remaining + 1]
		remaining -= LENGTHS[month]
	return "Dec 31"


## Day, date, clock time and moon phase for the HUD.
func describe() -> String:
	var hours := wrapf(6.0 + time_of_day_deg / 15.0, 0.0, 24.0)
	var stopped := world != null and not world.clock.daylight_cycle
	return "day %d (%s), %02d:%02d%s, %s (%d%%)" % [
		day, date_string(), int(hours), int(fmod(hours, 1.0) * 60.0), " (time stopped)" if stopped else "",
		moon_phase_name(), roundi(moon_illumination() * 100.0),
	]
