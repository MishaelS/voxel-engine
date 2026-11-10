class_name WeatherEffects
extends Node3D
## What the weather does, like the classic game:
## - draws rain (and snow in cold biomes; deserts stay dry) falling around
##   the player down to the first block in each column, as one sheet of
##   streaks per column turned toward the player, within 6 blocks (assets/textures/environment/rain.png and
##   snow.png, tools/make_item_textures.py), fading with the rain;
## - rain splashes where it lands and patters (ambient/rain), louder
##   outdoors; storms rumble;
## - each tick (world_tick): snow piles up on the ground in cold biomes while
##   it snows, still water there freezes, and in a storm lightning
##   (LightningBolt) strikes now and then (1 in 100000 ticks per column, like
##   the game's chunks).

const RADIUS := 6
const RAIN_PATH := "res://assets/textures/environment/rain.png"
const SNOW_PATH := "res://assets/textures/environment/snow.png"
## Columns around the player tried for snow and ice each tick.
const SURFACE_TRIES := 4
## Chance per tick per loaded column (as in the game, per chunk).
const LIGHTNING_CHANCE := 1.0 / 100000.0

var world: VoxelWorld

var _rain_mesh := ImmediateMesh.new()
var _snow_mesh := ImmediateMesh.new()
var _rain_material: ShaderMaterial
var _snow_material: ShaderMaterial
var _heights := {} # Vector2i -> [precipitation height, frame]
var _sound_wait := 0
var _frame := 0


func _ready() -> void:
	_rain_material = _material(RAIN_PATH, 1.0)
	_snow_material = _material(SNOW_PATH, 0.15)
	for pair: Array in [[_rain_mesh, _rain_material], [_snow_mesh, _snow_material]]:
		var instance := MeshInstance3D.new()
		instance.mesh = pair[0]
		instance.material_override = pair[1]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 64.0
		add_child(instance)


static func _material(path: String, speed: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/weather.gdshader")
	material.set_shader_parameter("streaks", load(path))
	material.set_shader_parameter("speed", speed)
	return material


func _process(_delta: float) -> void:
	_rain_mesh.clear_surfaces()
	_snow_mesh.clear_surfaces()
	var player := world.player as Player if world else null
	var strength := world.weather.rain_strength if world else 0.0
	if player == null or strength <= 0.0:
		return
	_frame += 1
	var eye := player.eye_position()
	var light := world.brightness_at(eye)
	for material: ShaderMaterial in [_rain_material, _snow_material]:
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("brightness", light)
	var center := Vector2i(floori(eye.x), floori(eye.z))
	var rain_open := false
	var snow_open := false
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			if dx * dx + dz * dz > RADIUS * RADIUS:
				continue
			var x := center.x + dx
			var z := center.y + dz
			var kind := _kind_at(x, z)
			if kind == "":
				continue
			var ground := _height(x, z)
			var bottom := maxf(ground, eye.y - RADIUS)
			var top := maxf(ground, eye.y + RADIUS)
			if top <= bottom:
				continue
			var mesh := _snow_mesh if kind == "snow" else _rain_mesh
			if mesh.get_surface_count() == 0 and not (rain_open if kind == "rain" else snow_open):
				mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				if kind == "rain":
					rain_open = true
				else:
					snow_open = true
			_sheet(mesh, x, z, bottom, top, eye)
	if rain_open:
		_rain_mesh.surface_end()
	if snow_open:
		_snow_mesh.surface_end()


## "rain", "snow" or "" (dry: deserts) for a column.
func _kind_at(x: int, z: int) -> String:
	var biome := world.biome_at(x, z)
	if biome == "desert":
		return ""
	return "snow" if biome in ["tundra", "taiga"] else "rain"


func _height(x: int, z: int) -> int:
	var key := Vector2i(x, z)
	var cached: Array = _heights.get(key, [])
	if cached.is_empty() or _frame - int(cached[1]) > 30:
		cached = [Weather.precipitation_height(world, x, z), _frame + randi_range(0, 10)]
		_heights[key] = cached
		if _heights.size() > 4000:
			_heights.clear()
	return cached[0]


## One sheet through the middle of a column, turned toward the player like
## the game's; the UV's x is the column's own (so neighbors don't streak
## alike), y the height.
func _sheet(mesh: ImmediateMesh, x: int, z: int, bottom: float, top: float, eye: Vector3) -> void:
	var offset := float(posmod(x * 3121 + z * 45238971, 16)) / 16.0
	var middle := Vector2(x + 0.5, z + 0.5)
	var to_eye := Vector2(eye.x, eye.z) - middle
	var across := Vector2(-to_eye.y, to_eye.x).normalized() * 0.5 if to_eye.length_squared() > 1e-4 else Vector2(0.5, 0)
	for corners: Array in [[middle - across, middle + across]]:
		var a := Vector3(corners[0].x, 0, corners[0].y)
		var b := Vector3(corners[1].x, 0, corners[1].y)
		var quad := [Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3(b.x, bottom, b.z), Vector3(a.x, bottom, a.z)]
		var uv := [Vector2(offset, top / 4.0), Vector2(offset + 1, top / 4.0), Vector2(offset + 1, bottom / 4.0),
			Vector2(offset, bottom / 4.0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			mesh.surface_set_uv(uv[k])
			mesh.surface_add_vertex(quad[k])


# --- World tick ----------------------------------------------------------------------

static func world_tick(world: VoxelWorld) -> void:
	var player := world.player as Player
	if player == null:
		return
	var weather := world.weather
	var center := Vector3i(player.global_position.floor())
	# Snow piles up and water freezes in the cold biomes.
	for i in SURFACE_TRIES:
		var x := center.x + randi_range(-64, 64)
		var z := center.z + randi_range(-64, 64)
		if randi_range(0, 15) != 0 or not world.is_inside(Vector3i(x, 0, z)) or not Weather.snows_at(world, x, z):
			continue
		var y := Weather.precipitation_height(world, x, z)
		var below := world.get_block(Vector3i(x, y - 1, z))
		if Blocks.get_type(below).name == "water" and world.get_block_light(Vector3i(x, y - 1, z)) < 10:
			world.set_block(Vector3i(x, y - 1, z), Blocks.id_of("ice"))
		elif weather.raining and world.get_block(Vector3i(x, y, z)) == Blocks.AIR \
				and Blocks.is_opaque_table[below] == 1 and Blocks.collides_table[below] == 1 \
				and world.get_block_light(Vector3i(x, y, z)) < 10:
			world.set_block(Vector3i(x, y, z), Blocks.id_of("snow_layer"))
	if weather.rain_strength <= 0.0:
		return
	# Splashes and the sound of rain where it lands near the player.
	_rain_effects(world, center, weather.rain_strength)
	# Lightning in a storm.
	if weather.is_storming():
		var columns := 128 * 128 / 16
		if randf() < LIGHTNING_CHANCE * columns * 16.0:
			var x := center.x + randi_range(-128, 128)
			var z := center.z + randi_range(-128, 128)
			var y := Weather.precipitation_height(world, x, z)
			if world.is_inside(Vector3i(x, y, z)) and rains_at(world, Vector3i(x, y, z)):
				LightningBolt.strike(world, Vector3i(x, y, z))


static func _rain_effects(world: VoxelWorld, center: Vector3i, strength: float) -> void:
	var count := int(30.0 * strength * strength)
	var sound_spot := Vector3.INF
	var splashes := 0
	for i in count:
		var x := center.x + randi_range(-10, 10)
		var z := center.z + randi_range(-10, 10)
		var y := Weather.precipitation_height(world, x, z)
		if absi(y - center.y) > 10 or not rains_at(world, Vector3i(x, y, z)):
			continue
		var below := world.get_block(Vector3i(x, y - 1, z))
		var point := Vector3(x + randf(), y + Blocks.height_table[below] - 1.0 + 0.05, z + randf())
		if splashes < 30:
			world.particles.rain_splash(point, Blocks.liquid_table[below] == 1)
			splashes += 1
		if randi_range(0, i + 1) == 0:
			sound_spot = point
	if sound_spot != Vector3.INF and randi_range(0, 2) < [0, 1, 2][mini(int(strength * 3.0), 2)] + 1:
		var player := world.player as Player
		var above := sound_spot.y > player.eye_position().y + 1.0 and Vector2(sound_spot.x - player.global_position.x,
			sound_spot.z - player.global_position.z).length() < 2.0
		Sounds.play("ambient/rain", sound_spot, 0.1 if above else 0.2, 0.5 if above else 1.0)


## Rain (not snow, not in deserts) falls on this cell right now.
static func rains_at(world: VoxelWorld, pos: Vector3i) -> bool:
	if not world.weather.raining or world.weather.rain_strength < 0.2:
		return false
	var biome := world.biome_at(pos.x, pos.z)
	if biome == "desert" or biome in ["tundra", "taiga"]:
		return false
	return Weather.is_open_to_sky(world, pos)
