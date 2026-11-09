class_name DayNightCycle
extends DirectionalLight3D
## The sun and the moon like the classic game: a day is 24000 ticks; the
## sun rises in the east, passes overhead at noon and sets in the west,
## the moon opposite it, along the classic "celestial angle" (a little
## faster around noon and midnight than at dawn and dusk). The moon has 8
## phases, one per day (day 0 is a full moon). Sky brightness and the night
## darkness of sky light (up to 11 light levels, like the classic game's
## skylightSubtracted) come from the same angle.
##
## During the day this light is the sunlight; at night it becomes the
## moonlight (Dynamic Lighting shader pack; Classic uses the light levels).
## Time comes from the world clock, interpolated between ticks.
##
## M - skip to the next day (time is changed by commands, not keys).
## Time stops with /gamerule doDaylightCycle false.

const PHASE_NAMES: Array[String] = [
	"full moon", "waning gibbous", "last quarter", "waning crescent",
	"new moon", "waxing crescent", "first quarter", "waxing gibbous",
]
## Light levels sky light loses at midnight (the classic value).
const MAX_SKY_DARKNESS := 11.0

@export var world_environment: WorldEnvironment
## World whose clock sets the time.
@export var world: VoxelWorld

## Time of day in ticks (0 = sunrise, 6000 = noon) and the day number.
var day_time := 1000.0
var day := 0

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
	if event.is_action_pressed("next_day"):
		world.clock.add_day_time(WorldClock.TICKS_PER_DAY)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if world:
		var clock := world.clock
		var time := clock.day_time
		if clock.daylight_cycle and not TickLoop.frozen:
			time += TickLoop.alpha
		day = floori(time / WorldClock.TICKS_PER_DAY)
		day_time = fposmod(time, WorldClock.TICKS_PER_DAY)
	_apply()


## The classic celestial angle (0 = noon, 0.25 = sunset, 0.5 = midnight,
## 0.75 = sunrise): the sun moves a bit faster around noon and midnight.
func celestial_angle() -> float:
	return angle_at(day_time)


static func angle_at(time: float) -> float:
	var f := fposmod(time, WorldClock.TICKS_PER_DAY) / WorldClock.TICKS_PER_DAY - 0.25
	if f < 0.0:
		f += 1.0
	if f > 1.0:
		f -= 1.0
	var eased := 1.0 - (cos(f * PI) + 1.0) / 2.0
	return f + (eased - f) / 3.0


## Unit vector toward the sun: east (+X) at sunrise, up at noon, west at
## sunset (the classic sun path).
func sun_direction() -> Vector3:
	var angle := celestial_angle() * TAU
	return Vector3(-sin(angle), cos(angle), 0.0)


## Brightness of the sky, 0 (night) .. 1 (day), the classic formula.
func sky_brightness() -> float:
	return clampf(cos(celestial_angle() * TAU) * 2.0 + 0.5, 0.0, 1.0)


## Night like the classic game's bed check: the sky has lost 4 or more
## light levels.
static func is_night(time: float) -> bool:
	var brightness := clampf(cos(angle_at(time) * TAU) * 2.0 + 0.5, 0.0, 1.0)
	return (1.0 - brightness) * MAX_SKY_DARKNESS >= 4.0


## Light levels sky light loses now (0 by day .. 11 at night).
func sky_darkness() -> float:
	return (1.0 - sky_brightness()) * MAX_SKY_DARKNESS


## Moon phase index 0..7 (0 = full moon), one per day like the classic game.
func moon_phase_index() -> int:
	return posmod(day, 8)


## Moon phase 0..1 for the sky shader (0 = new, 0.5 = full).
func moon_phase() -> float:
	return fposmod(0.5 + moon_phase_index() / 8.0, 1.0)


## Lit part of the moon disc: 0 = new moon, 1 = full moon.
func moon_illumination() -> float:
	return 0.5 - 0.5 * cos(moon_phase() * TAU)


func moon_phase_name() -> String:
	return PHASE_NAMES[moon_phase_index()]


func _apply() -> void:
	var to_sun := sun_direction()
	var is_day := to_sun.y >= 0.0
	var to_light := to_sun if is_day else -to_sun
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


## Day, clock time and moon phase for the HUD.
func describe() -> String:
	var hours := fposmod(6.0 + day_time / 1000.0, 24.0)
	var stopped := world != null and not world.clock.daylight_cycle
	return "day %d, %02d:%02d%s, %s (%d%%)" % [
		day, int(hours), int(fmod(hours, 1.0) * 60.0), " (time stopped)" if stopped else "",
		moon_phase_name(), roundi(moon_illumination() * 100.0),
	]
