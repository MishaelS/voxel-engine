class_name WeatherEffects
extends Node3D
## What the weather does, like the classic game:
## - draws snow and rain like Beta 1.7.3's EntityRenderer.renderRainSnow:
##   in every column within 5 blocks (10 with Fancy graphics) two crossed
##   upright sheets (environment/snow.png in the cold biomes,
##   environment/rain.png where it rains: not in deserts) from the first
##   solid block or liquid up to 5 / 10 blocks above the eyes. Each column
##   gets its own numbers from java.util.Random seeded by its position like
##   the game's: rain falls at its own speed (3..4 times a 32 tick cycle,
##   started at its own point), snow drifts slowly down and sideways each
##   its own way; lit by the light there (rain: at the top of the world,
##   x0.85 + 0.15), more see-through toward the edge. What moves with time
##   is worked out by the shader (shaders/weather.gdshader); the sheets are
##   made again when the player moves to another block or every 20 frames;
## - rain splashes where it lands and patters (ambient/rain), louder
##   outdoors; storms rumble;
## - each tick (world_tick): snow piles up on the ground in cold biomes while
##   it snows, still water there freezes, and in a storm lightning
##   (LightningBolt) strikes now and then (1 in 100000 ticks per column, like
##   the game's chunks).

const RAIN_PATH := "res://assets/textures/environment/rain.png"
const SNOW_PATH := "res://assets/textures/environment/snow.png"
## Columns around the player tried for snow and ice each tick.
const SURFACE_TRIES := 4
## Chance per tick per loaded column (as in the game, per chunk).
const LIGHTNING_CHANCE := 1.0 / 100000.0
## The sheets are made again at least this often (frames): the ground and
## the light under them change.
const REBUILD_FRAMES := 20

var world: VoxelWorld

var _rain := MeshInstance3D.new()
var _snow := MeshInstance3D.new()
var _rain_material: ShaderMaterial
var _snow_material: ShaderMaterial
var _columns := {} # Vector2i -> [kind, numbers...] (the column's Random numbers)
var _built_at := Vector3i.MAX
var _built_radius := 0
var _frames := 0


func _ready() -> void:
	_rain_material = _material(RAIN_PATH, false)
	_snow_material = _material(SNOW_PATH, true)
	for pair: Array in [[_rain, _rain_material], [_snow, _snow_material]]:
		var instance: MeshInstance3D = pair[0]
		instance.material_override = pair[1]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 64.0
		add_child(instance)


static func _material(path: String, snow: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/weather.gdshader")
	material.set_shader_parameter("streaks", TexturePacks.load_texture(path))
	material.set_shader_parameter("snow", snow)
	return material


func _process(_delta: float) -> void:
	var player := world.player as Player if world else null
	var strength := world.weather.rain_strength if world else 0.0
	if player == null or strength <= 0.0:
		_rain.visible = false
		_snow.visible = false
		_built_at = Vector3i.MAX
		return
	_rain.visible = true
	_snow.visible = true
	var eye := player.eye_position()
	var radius := 5 if Blocks.is_fast_graphics() else 10
	var cell := Vector3i(eye.floor())
	_frames += 1
	if cell != _built_at or radius != _built_radius or _frames >= REBUILD_FRAMES:
		_frames = 0
		_built_at = cell
		_built_radius = radius
		_build(cell, radius)
	for material: ShaderMaterial in [_rain_material, _snow_material]:
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("ticks", float(TickLoop.tick_count))
		material.set_shader_parameter("partial", TickLoop.alpha)
		material.set_shader_parameter("eye", Vector2(eye.x, eye.z))
		material.set_shader_parameter("radius", float(radius))


## The sheets of every column around the player's block.
func _build(at: Vector3i, radius: int) -> void:
	var meshes := [_Sheets.new(), _Sheets.new()] # rain, snow
	if _columns.size() > 4096:
		_columns.clear()
	for x in range(at.x - radius, at.x + radius + 1):
		for z in range(at.z - radius, at.z + radius + 1):
			var column := Vector2i(x, z)
			var numbers: Array = _columns.get(column, [])
			if numbers.is_empty():
				numbers = _numbers(x, z)
				_columns[column] = numbers
			if numbers[0] == "":
				continue
			var ground := maxi(_top_solid(x, z), 0)
			var bottom := maxi(at.y - radius, ground)
			var top := maxi(at.y + radius, ground)
			if bottom == top:
				continue
			var snow: bool = numbers[0] == "snow"
			# The light: snow's at the player's height (or the ground), rain's
			# at the top of the world.
			var light := world.brightness_at(Vector3(x, maxi(ground, at.y), z)) if snow \
				else world.brightness_at(Vector3(x, world.height - 1, z)) * 0.85 + 0.15
			(meshes[1 if snow else 0] as _Sheets).add(x, z, bottom, top, light,
				PackedFloat32Array([numbers[1], numbers[2], numbers[3], numbers[4]]))
	_rain.mesh = (meshes[0] as _Sheets).to_mesh()
	_snow.mesh = (meshes[1] as _Sheets).to_mesh()


## A column's weather and its Random numbers like the game's: [kind, a, b,
## c, d]. Snow: a = nextFloat (sideways start), b = nextGaussian (sideways
## drift), c = nextFloat (down start), d = nextGaussian (down drift). Rain:
## a = nextFloat (speed: 3 + a), b = the column's start in the 32 tick
## cycle.
func _numbers(x: int, z: int) -> Array:
	var kind := _kind_at(x, z)
	# (Java int arithmetic: wraps at 32 bits)
	var seed_value := _int32(x * x * 3121 + x * 45238971 + z * z * 418711 + z * 13761)
	var random := _JavaRandom.new(seed_value)
	if kind == "snow":
		var a := random.next_float()
		var b := random.next_gaussian()
		var c := random.next_float()
		var d := random.next_gaussian()
		return [kind, a, b, c, d]
	if kind == "rain":
		return [kind, random.next_float(), float(seed_value & 31), 0.0, 0.0]
	return [""]


static func _int32(value: int) -> int:
	value &= 0xFFFFFFFF
	return value - 0x100000000 if value >= 0x80000000 else value


## "rain", "snow" or "" (dry: deserts) for a column.
func _kind_at(x: int, z: int) -> String:
	var biome := world.biome_at(x, z)
	if biome == "desert":
		return ""
	return "snow" if biome in ["tundra", "taiga"] else "rain"


## Beta's findTopSolidBlock: the cell above the highest block that stops
## things falling (a solid one or a liquid; not flowers, torches, tall
## grass); chunks of only air are skipped whole.
func _top_solid(x: int, z: int) -> int:
	var chunks: Dictionary = world.get("_chunks")
	var column := (x & 15) + ((z & 15) << 4)
	for cy in range((WorldGenerator.HEIGHT - 1) >> 4, -1, -1):
		var data: ChunkData = chunks.get(Vector3i(x >> 4, cy, z >> 4))
		if data == null or data.air_count == ChunkData.VOLUME:
			continue
		var blocks := data.blocks
		for ly in range(15, -1, -1):
			var id := blocks[column + (ly << 8)]
			if id != Blocks.AIR and (Blocks.collides_table[id] == 1 or Blocks.liquid_table[id] == 1):
				return (cy << 4) + ly + 1
	return 0


## The two crossed sheets of the columns: like the game's quads, u 0..1
## across, v = height / 4; UV2 the column's middle (how far from the
## player), CUSTOM0 the column's numbers, CUSTOM1.r its light (floats: vertex
## colors would be cut to 0..1).
class _Sheets:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var middles := PackedVector2Array()
	var numbers := PackedFloat32Array()
	var lights := PackedFloat32Array()
	var indices := PackedInt32Array()

	func add(x: int, z: int, bottom: int, top: int, light: float, column: PackedFloat32Array) -> void:
		var middle := Vector2(x + 0.5, z + 0.5)
		for plane in 2:
			var a := Vector3(x, 0, z + 0.5) if plane == 0 else Vector3(x + 0.5, 0, z)
			var b := Vector3(x + 1, 0, z + 0.5) if plane == 0 else Vector3(x + 0.5, 0, z + 1)
			var start := vertices.size()
			vertices.append_array(PackedVector3Array([Vector3(a.x, bottom, a.z), Vector3(b.x, bottom, b.z),
				Vector3(b.x, top, b.z), Vector3(a.x, top, a.z)]))
			uvs.append_array(PackedVector2Array([Vector2(0, bottom / 4.0), Vector2(1, bottom / 4.0),
				Vector2(1, top / 4.0), Vector2(0, top / 4.0)]))
			for k in 4:
				middles.append(middle)
				numbers.append_array(column)
				lights.append_array(PackedFloat32Array([light, 0.0, 0.0, 0.0]))
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))

	func to_mesh() -> ArrayMesh:
		if vertices.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = middles
		arrays[Mesh.ARRAY_CUSTOM0] = numbers
		arrays[Mesh.ARRAY_CUSTOM1] = lights
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
		return mesh


## java.util.Random, number for number (the game seeds one per column).
class _JavaRandom:
	const MULTIPLIER := 0x5DEECE66D
	const MASK := (1 << 48) - 1
	var _seed := 0
	var _next_gaussian := 0.0
	var _has_next_gaussian := false

	func _init(seed_value: int) -> void:
		_seed = (seed_value ^ MULTIPLIER) & MASK

	func _next(bits: int) -> int:
		_seed = (_seed * MULTIPLIER + 0xB) & MASK
		var value := _seed >> (48 - bits)
		# (Java's int: the top bit is the sign)
		return value - (1 << bits) if bits == 32 and value >= (1 << 31) else value

	func next_float() -> float:
		return _next(24) / float(1 << 24)

	func next_double() -> float:
		return float((_next(26) << 27) + _next(27)) / float(1 << 53)

	func next_gaussian() -> float:
		if _has_next_gaussian:
			_has_next_gaussian = false
			return _next_gaussian
		var v1 := 0.0
		var v2 := 0.0
		var s := 0.0
		while true:
			v1 = 2.0 * next_double() - 1.0
			v2 = 2.0 * next_double() - 1.0
			s = v1 * v1 + v2 * v2
			if s < 1.0 and s != 0.0:
				break
		var multiplier := sqrt(-2.0 * log(s) / s)
		_next_gaussian = v2 * multiplier
		_has_next_gaussian = true
		return v1 * multiplier


# --- World tick ----------------------------------------------------------------------

static func world_tick(world: VoxelWorld) -> void:
	var player := world.player as Player
	# Around every player (a dedicated server has none of its own).
	for at in world.player_positions(false):
		_world_tick_at(world, Vector3i(at.floor()), player != null and at == player.global_position)


static func _world_tick_at(world: VoxelWorld, center: Vector3i, own: bool) -> void:
	var weather := world.weather
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
	if own:
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


## Where rain or snow lands near the player: rain splashes on the ground and
## on water, snow melts into water, and both hiss into steam on lava, fire
## and torches (with a fizz now and then).
static func _rain_effects(world: VoxelWorld, center: Vector3i, strength: float) -> void:
	var count := int(30.0 * strength * strength)
	var sound_spot := Vector3.INF
	var splashes := 0
	var fizzes := 0
	for i in count:
		var x := center.x + randi_range(-10, 10)
		var z := center.z + randi_range(-10, 10)
		var y := Weather.precipitation_height(world, x, z)
		if absi(y - center.y) > 10:
			continue
		var raining := rains_at(world, Vector3i(x, y, z))
		if not raining and not snows_on(world, Vector3i(x, y, z)):
			continue
		var below := world.get_block(Vector3i(x, y - 1, z))
		var family := Blocks.family_of(below)
		if family == "lava" or family == "fire" or (family.ends_with("torch") and not family.begins_with("unlit_")):
			# Hot: the drops and flakes hiss into steam.
			var top := Vector3(x + 0.5, y - 1, z + 0.5) + (TorchBehavior.FLOOR_TIP - Vector3(0.5, 0, 0.5) \
				if family.ends_with("torch") else Vector3(0, Blocks.height_table[below] + 0.05, 0))
			if splashes < 30 and randi_range(0, 2) == 0:
				world.particles.steam(top, 1 if family.ends_with("torch") else 2)
				splashes += 1
			if fizzes < 1 and randi_range(0, 9) == 0:
				Sounds.play("random/fizz", top, 0.15, randf_range(2.0, 2.6))
				fizzes += 1
			continue
		var point := Vector3(x + randf(), y + Blocks.height_table[below] - 1.0 + 0.05, z + randf())
		if not raining:
			if Blocks.liquid_table[below] == 1 and splashes < 30:
				world.particles.snow_melt(point) # snow falls on water
				splashes += 1
			continue
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


## Snow falls on this cell right now (cold biomes, open to the sky).
static func snows_on(world: VoxelWorld, pos: Vector3i) -> bool:
	if not world.weather.raining or world.weather.rain_strength < 0.2:
		return false
	return Weather.snows_at(world, pos.x, pos.z) and Weather.is_open_to_sky(world, pos)


## Rain (not snow, not in deserts) falls on this cell right now.
static func rains_at(world: VoxelWorld, pos: Vector3i) -> bool:
	if not world.weather.raining or world.weather.rain_strength < 0.2:
		return false
	var biome := world.biome_at(pos.x, pos.z)
	if biome == "desert" or biome in ["tundra", "taiga"]:
		return false
	return Weather.is_open_to_sky(world, pos)
