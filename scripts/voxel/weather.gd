class_name Weather
extends RefCounted
## Weather like the classic game (Beta 1.7.3 WorldInfo):
## - rain and thunder come and go on their own timers: clear for
##   12000..180000 ticks, then rain for 3600..15600; thunder runs its own
##   timer the same way and storms only while it also rains;
## - the rain and thunder strengths fade in and out by 0.01 a tick;
## - rain falls as snow in cold biomes (WeatherEffects draws it).
## Only while doWeatherCycle is on do the timers run; /weather sets it.

var raining := false
var thundering := false
var rain_time := 0
var thunder_time := 0
## 0..1, fading with the rain (sky color, light, sound).
var rain_strength := 0.0
var thunder_strength := 0.0
var cycle := true


func _init() -> void:
	rain_time = randi_range(12000, 180000)
	thunder_time = randi_range(12000, 180000)


func tick() -> void:
	if cycle:
		thunder_time -= 1
		if thunder_time <= 0:
			thundering = not thundering
			thunder_time = randi_range(3600, 15600) if thundering else randi_range(12000, 180000)
		rain_time -= 1
		if rain_time <= 0:
			raining = not raining
			rain_time = randi_range(3600, 15600) if raining else randi_range(12000, 180000)
	rain_strength = move_toward(rain_strength, 1.0 if raining else 0.0, 0.01)
	thunder_strength = move_toward(thunder_strength, 1.0 if raining and thundering else 0.0, 0.01)


## Sets the weather (/weather): "clear", "rain" or "thunder" for `ticks`.
func set_weather(kind: String, ticks: int) -> void:
	raining = kind != "clear"
	thundering = kind == "thunder"
	rain_time = ticks
	thunder_time = ticks


func is_storming() -> bool:
	return raining and thundering and thunder_strength > 0.9


## Light levels the weather takes off the sky light, like the game's
## (rain up to 3, a storm up to 5 more... out of the 11 a night takes).
func sky_darkness() -> float:
	return rain_strength * 3.0 + thunder_strength * 2.0


func save_state() -> Dictionary:
	return {"raining": raining, "thundering": thundering, "rain_time": rain_time, "thunder_time": thunder_time,
		"rain_strength": rain_strength, "thunder_strength": thunder_strength}


func load_state(saved: Dictionary) -> void:
	raining = saved.get("raining", false)
	thundering = saved.get("thundering", false)
	rain_time = saved.get("rain_time", rain_time)
	thunder_time = saved.get("thunder_time", thunder_time)
	rain_strength = saved.get("rain_strength", 1.0 if raining else 0.0)
	thunder_strength = saved.get("thunder_strength", 0.0)


## Whether rain (or snow) reaches this cell from the sky: nothing above it.
static func is_open_to_sky(world: VoxelWorld, pos: Vector3i) -> bool:
	return pos.y >= precipitation_height(world, pos.x, pos.z)


## The lowest cell rain falls into in a column: above the highest block that
## isn't air (leaves, glass and water stop it too).
static func precipitation_height(world: VoxelWorld, x: int, z: int) -> int:
	for y in range(WorldGenerator.HEIGHT - 1, -1, -1):
		if world.get_block(Vector3i(x, y, z)) != Blocks.AIR:
			return y + 1
	return 0


## Snow instead of rain here (the cold biomes).
static func snows_at(world: VoxelWorld, x: int, z: int) -> bool:
	return world.biome_at(x, z) in ["tundra", "taiga"]
