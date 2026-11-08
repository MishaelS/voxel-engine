class_name BetaGenerator
extends WorldGenerator
## Terrain in the style of Minecraft Beta 1.7.3 (an own implementation of
## the same approach):
##
## 1. Terrain shape: a 3D density field sampled on a coarse grid (one point
##    every 4 x 8 x 4 blocks) and interpolated. Two "limit" noises give a
##    low and a high density, a "main" noise blends between them (this makes
##    the overhangs and floating bits typical of the era); a large-scale
##    depth noise lifts or lowers the land, a scale noise and the biome's
##    dryness set how hilly it is. Density > 0 is stone; below sea level
##    (64) empty space is water.
## 2. Biomes from temperature and humidity with the classic table (tundra,
##    taiga, swampland, forest, seasonal forest, rainforest, savanna,
##    shrubland, plains, desert), each with its own surface and trees.
## 3. Surface: grass / dirt layers, sand and gravel beaches near sea level,
##    sandstone under sand, an uneven bedrock floor.
## 4. Caves: "worm" tunnels and rooms that start in nearby columns and wind
##    through this one.
## 5. Ores and dirt / gravel pockets at the classic heights and amounts.
## 6. Trees: oak, birch, spruce and pine depending on the biome; ice on cold
##    water.

const GRID_X := 4  # blocks per density cell horizontally
const GRID_Y := 8  # blocks per density cell vertically
const CELLS_X := 16 / GRID_X
const CELLS_Y := HEIGHT / GRID_Y
const LIMIT_AMPLITUDE := 40.0
const CAVE_RANGE := 8 # columns around this one where caves can start

## Biome table: surface blocks, grass, tree count and kinds.
const BIOMES := {
	"tundra": {"top": "snowy_grass", "filler": "dirt", "trees": -20, "cold": true},
	"taiga": {"top": "snowy_grass", "filler": "dirt", "trees": 5, "cold": true},
	"swampland": {"top": "grass_swamp", "filler": "dirt", "trees": 0, "cold": false},
	"forest": {"top": "grass_forest", "filler": "dirt", "trees": 5, "cold": false},
	"seasonal_forest": {"top": "grass_forest", "filler": "dirt", "trees": 2, "cold": false},
	"rainforest": {"top": "grass_forest", "filler": "dirt", "trees": 5, "cold": false},
	"savanna": {"top": "grass_savanna", "filler": "dirt", "trees": 0, "cold": false},
	"shrubland": {"top": "grass_savanna", "filler": "dirt", "trees": 0, "cold": false},
	"plains": {"top": "grass_plains", "filler": "dirt", "trees": -20, "cold": false},
	"desert": {"top": "sand", "filler": "sand", "trees": -20, "cold": false},
}

## [block, veins per column, vein size, max height] like the classic game.
const ORES := [
	["dirt", 20, 32, 128],
	["gravel", 10, 32, 128],
	["coal_ore", 20, 16, 128],
	["iron_ore", 20, 8, 64],
	["gold_ore", 2, 8, 32],
	["redstone_ore", 8, 7, 16],
	["diamond_ore", 1, 7, 16],
	["lapis_ore", 1, 6, 32],
]

var _min_noise := FastNoiseLite.new()
var _max_noise := FastNoiseLite.new()
var _main_noise := FastNoiseLite.new()
var _depth_noise := FastNoiseLite.new()
var _scale_noise := FastNoiseLite.new()
var _temperature_noise := FastNoiseLite.new()
var _humidity_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _sand_noise := FastNoiseLite.new()
var _gravel_noise := FastNoiseLite.new()
var _soil_noise := FastNoiseLite.new()
var _tree_noise := FastNoiseLite.new()

var _id := {} # block name -> id (read-only after _init, safe across threads)


func _init(seed_value: int) -> void:
	super(seed_value)
	_setup(_min_noise, 1, 0.0052, 8)
	_setup(_max_noise, 2, 0.0052, 8)
	_setup(_main_noise, 3, 0.0167, 6)
	_setup(_depth_noise, 4, 0.0015, 6)
	_setup(_scale_noise, 5, 0.0011, 4)
	_setup(_temperature_noise, 6, 0.004, 4)
	_setup(_humidity_noise, 7, 0.006, 4)
	_setup(_detail_noise, 8, 0.12, 2)
	_setup(_sand_noise, 9, 0.03, 3)
	_setup(_gravel_noise, 10, 0.03, 3)
	_setup(_soil_noise, 11, 0.06, 3)
	_setup(_tree_noise, 12, 0.02, 2)
	for block in Blocks.types:
		_id[block.name] = block.id


func _setup(noise: FastNoiseLite, salt: int, frequency: float, octaves: int) -> void:
	noise.seed = hash([world_seed, salt])
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


# --- Climate and biomes ------------------------------------------------------------

func temperature(x: float, z: float) -> float:
	return clampf(0.62 + _temperature_noise.get_noise_2d(x, z) * 0.9 + _detail_noise.get_noise_2d(x, z) * 0.03, 0.0, 1.0)


func humidity(x: float, z: float) -> float:
	return clampf(0.5 + _humidity_noise.get_noise_2d(x, z) * 0.9 + _detail_noise.get_noise_2d(z, x) * 0.03, 0.0, 1.0)


## The classic biome table.
static func biome_for(temp: float, humid: float) -> String:
	if temp < 0.1:
		return "tundra"
	humid *= temp
	if humid < 0.2:
		if temp < 0.5:
			return "tundra"
		return "savanna" if temp < 0.95 else "desert"
	if humid > 0.5 and temp < 0.7:
		return "swampland"
	if temp < 0.5:
		return "taiga"
	if temp < 0.97:
		return "shrubland" if humid < 0.35 else "forest"
	if humid < 0.45:
		return "plains"
	return "seasonal_forest" if humid < 0.9 else "rainforest"


func biome_name(x: int, z: int) -> String:
	return biome_for(temperature(x, z), humidity(x, z))


# --- Generation --------------------------------------------------------------------

func generate_blocks(cx: int, cz: int) -> PackedByteArray:
	var blocks := super(cx, cz)
	var biomes: Array[String] = []
	for z in 16:
		for x in 16:
			biomes.append(biome_name(cx * 16 + x, cz * 16 + z))
	_shape_terrain(blocks, cx, cz)
	_replace_surface(blocks, cx, cz, biomes)
	_carve_caves(blocks, cx, cz)
	var rng := column_rng(cx, cz, 100)
	_place_ores(blocks, rng)
	_place_trees(blocks, cx, cz, biomes, rng)
	_freeze(blocks, biomes)
	return blocks


## Step 1: density field on a coarse grid, interpolated to blocks.
func _shape_terrain(blocks: PackedByteArray, cx: int, cz: int) -> void:
	var stone: int = _id["stone"]
	var water: int = _id["water"]
	var stride_y := CELLS_Y + 1
	var stride_z := (CELLS_X + 1) * stride_y
	var density := PackedFloat32Array()
	density.resize((CELLS_X + 1) * (CELLS_X + 1) * stride_y)

	for gx in CELLS_X + 1:
		for gz in CELLS_X + 1:
			var wx := float(cx * 16 + gx * GRID_X)
			var wz := float(cz * 16 + gz * GRID_X)
			var temp := temperature(wx, wz)
			var humid := humidity(wx, wz) * temp
			var dryness := 1.0 - humid
			dryness *= dryness
			dryness *= dryness
			var vegetation := 1.0 - dryness

			var scale := (_scale_noise.get_noise_2d(wx, wz) * 1000.0 + 256.0) / 512.0 * vegetation
			if scale > 1.0:
				scale = 1.0
			var depth := _depth_noise.get_noise_2d(wx, wz) * 6.0
			if depth < 0.0:
				depth = -depth * 0.3
			depth = depth * 3.0 - 2.0
			if depth < 0.0:
				depth /= 2.0
				if depth < -1.0:
					depth = -1.0
				depth /= 1.4
				depth /= 2.0
				scale = 0.0
			else:
				if depth > 1.0:
					depth = 1.0
				depth /= 8.0
			if scale < 0.0:
				scale = 0.0
			scale += 0.5
			depth = depth * CELLS_Y / 16.0
			var center := CELLS_Y / 2.0 + 0.5 + depth * 4.0

			for gy in stride_y:
				var wy := float(gy * GRID_Y)
				var offset := (gy - center) * 12.0 / scale
				if offset < 0.0:
					offset *= 4.0
				var low := _min_noise.get_noise_3d(wx, wy * 0.5, wz) * LIMIT_AMPLITUDE
				var high := _max_noise.get_noise_3d(wx, wy * 0.5, wz) * LIMIT_AMPLITUDE
				var mix := (_main_noise.get_noise_3d(wx, wy * 0.25, wz) * 2.5 + 1.0) * 0.5
				var value := low if mix < 0.0 else (high if mix > 1.0 else lerpf(low, high, mix))
				value -= offset
				if gy > CELLS_Y - 3:
					var fade := (gy - (CELLS_Y - 3)) / 3.0
					value = value * (1.0 - fade) - 10.0 * fade
				density[gx * stride_z + gz * stride_y + gy] = value

	# Trilinear interpolation inside every cell.
	for gx in CELLS_X:
		for gz in CELLS_X:
			for gy in CELLS_Y:
				var base := gx * stride_z + gz * stride_y + gy
				var d000 := density[base]
				var d001 := density[base + stride_y]
				var d100 := density[base + stride_z]
				var d101 := density[base + stride_z + stride_y]
				var d010 := density[base + 1]
				var d011 := density[base + stride_y + 1]
				var d110 := density[base + stride_z + 1]
				var d111 := density[base + stride_z + stride_y + 1]
				for sy in GRID_Y:
					var ty := sy / float(GRID_Y)
					var y := gy * GRID_Y + sy
					var a00 := lerpf(d000, d010, ty)
					var a01 := lerpf(d001, d011, ty)
					var a10 := lerpf(d100, d110, ty)
					var a11 := lerpf(d101, d111, ty)
					for sx in GRID_X:
						var tx := sx / float(GRID_X)
						var b0 := lerpf(a00, a10, tx)
						var b1 := lerpf(a01, a11, tx)
						var x := gx * GRID_X + sx
						for sz in GRID_X:
							var value := lerpf(b0, b1, sz / float(GRID_X))
							var id := Blocks.AIR
							if value > 0.0:
								id = stone
							elif y < SEA_LEVEL:
								id = water
							if id != Blocks.AIR:
								blocks[index(x, y, gz * GRID_X + sz)] = id


## Step 3: biome surface, beaches and bedrock, top-down per block column.
func _replace_surface(blocks: PackedByteArray, cx: int, cz: int, biomes: Array[String]) -> void:
	var rng := column_rng(cx, cz, 1)
	var stone: int = _id["stone"]
	var water: int = _id["water"]
	var sand: int = _id["sand"]
	var gravel: int = _id["gravel"]
	var sandstone: int = _id["sandstone"]
	var bedrock: int = _id["bedrock"]
	for z in 16:
		for x in 16:
			var wx := float(cx * 16 + x)
			var wz := float(cz * 16 + z)
			var biome: Dictionary = BIOMES[biomes[z * 16 + x]]
			var sand_beach := _sand_noise.get_noise_2d(wx, wz) + rng.randf() * 0.2 > 0.0
			var gravel_beach := _gravel_noise.get_noise_2d(wz, wx) * 15.0 + rng.randf() * 0.2 > 3.0
			var soil_depth := int(_soil_noise.get_noise_2d(wx, wz) * 5.0 + 3.0 + rng.randf() * 0.25)
			var top: int = _id[biome.top]
			var filler: int = _id[biome.filler]
			var depth_left := -1
			for y in range(HEIGHT - 1, -1, -1):
				var i := index(x, y, z)
				if y <= rng.randi_range(0, 4):
					blocks[i] = bedrock
					continue
				var id := blocks[i]
				if id == Blocks.AIR:
					depth_left = -1
					continue
				if id != stone:
					continue # water
				if depth_left == -1:
					if soil_depth <= 0:
						top = Blocks.AIR
						filler = stone
					elif y >= SEA_LEVEL - 4 and y <= SEA_LEVEL + 1:
						top = _id[biome.top]
						filler = _id[biome.filler]
						if gravel_beach:
							top = Blocks.AIR
							filler = gravel
						if sand_beach:
							top = sand
							filler = sand
					if y < SEA_LEVEL and top == Blocks.AIR:
						top = water
					depth_left = soil_depth
					blocks[i] = top if y >= SEA_LEVEL - 1 else filler
				elif depth_left > 0:
					depth_left -= 1
					blocks[i] = filler
					if depth_left == 0 and filler == sand:
						depth_left = rng.randi_range(0, 3)
						filler = sandstone


## Step 4: worm caves from this and nearby columns, carved where they pass
## through this column.
func _carve_caves(blocks: PackedByteArray, cx: int, cz: int) -> void:
	for ox in range(-CAVE_RANGE, CAVE_RANGE + 1):
		for oz in range(-CAVE_RANGE, CAVE_RANGE + 1):
			var rng := column_rng(cx + ox, cz + oz, 2)
			var count := rng.randi_range(0, rng.randi_range(0, rng.randi_range(0, 39) + 1))
			if rng.randi_range(0, 14) != 0:
				count = 0
			for i in count:
				var start := Vector3(
					(cx + ox) * 16 + rng.randi_range(0, 15),
					rng.randi_range(0, rng.randi_range(0, 119) + 8),
					(cz + oz) * 16 + rng.randi_range(0, 15))
				var tunnels := 1
				if rng.randi_range(0, 3) == 0:
					_carve_tunnel(blocks, cx, cz, rng.randi(), start, 1.0 + rng.randf() * 6.0, 0.0, 0.0, -1, -1, 0.5)
					tunnels += rng.randi_range(0, 3)
				for t in tunnels:
					var yaw := rng.randf() * TAU
					var pitch := (rng.randf() - 0.5) * 2.0 / 8.0
					var width := rng.randf() * 2.0 + rng.randf()
					if rng.randi_range(0, 9) == 0:
						width *= rng.randf() * rng.randf() * 3.0 + 1.0
					_carve_tunnel(blocks, cx, cz, rng.randi(), start, width, yaw, pitch, 0, 0, 1.0)


## One tunnel (or a room if step == -1): a random walk that carves
## ellipsoids. May split into two branches.
func _carve_tunnel(blocks: PackedByteArray, cx: int, cz: int, seed_value: int, pos: Vector3,
		width: float, yaw: float, pitch: float, step: int, length: int, height_ratio: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var center_x := cx * 16 + 8.0
	var center_z := cz * 16 + 8.0
	var yaw_change := 0.0
	var pitch_change := 0.0
	if length <= 0:
		length = CAVE_RANGE * 16 - 16
		length -= rng.randi_range(0, length / 4)
	var is_room := step == -1
	if is_room:
		step = length / 2
	var split_at := rng.randi_range(length / 4, length / 2 + length / 4)
	var steep := rng.randi_range(0, 5) == 0

	while step < length:
		var radius := 1.5 + sin(step * PI / length) * width
		var radius_y := radius * height_ratio
		pos += Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
		pitch *= 0.92 if steep else 0.7
		pitch += pitch_change * 0.1
		yaw += yaw_change * 0.1
		pitch_change *= 0.9
		yaw_change *= 0.75
		pitch_change += (rng.randf() - rng.randf()) * rng.randf() * 2.0
		yaw_change += (rng.randf() - rng.randf()) * rng.randf() * 4.0

		if not is_room and step == split_at and width > 1.0:
			_carve_tunnel(blocks, cx, cz, rng.randi(), pos, rng.randf() * 0.5 + 0.5, yaw - PI / 2.0, pitch / 3.0, step, length, 1.0)
			_carve_tunnel(blocks, cx, cz, rng.randi(), pos, rng.randf() * 0.5 + 0.5, yaw + PI / 2.0, pitch / 3.0, step, length, 1.0)
			return
		step += 1
		if not is_room and rng.randi_range(0, 3) == 0:
			continue

		# Stop when this tunnel can no longer reach the column.
		var dx := pos.x - center_x
		var dz := pos.z - center_z
		var remaining := float(length - step)
		var reach := width + 2.0 + 16.0
		if dx * dx + dz * dz - remaining * remaining > reach * reach:
			return
		if absf(dx) > 8.0 + radius * 2.0 or absf(dz) > 8.0 + radius * 2.0:
			continue
		_carve_ellipsoid(blocks, cx, cz, pos, radius, radius_y)
		if is_room:
			return


func _carve_ellipsoid(blocks: PackedByteArray, cx: int, cz: int, center: Vector3, radius: float, radius_y: float) -> void:
	var water: int = _id["water"]
	var bedrock: int = _id["bedrock"]
	var min_x := maxi(floori(center.x - radius) - cx * 16 - 1, 0)
	var max_x := mini(floori(center.x + radius) - cx * 16 + 1, 15)
	var min_z := maxi(floori(center.z - radius) - cz * 16 - 1, 0)
	var max_z := mini(floori(center.z + radius) - cz * 16 + 1, 15)
	var min_y := maxi(floori(center.y - radius_y) - 1, 1)
	var max_y := mini(floori(center.y + radius_y) + 1, HEIGHT - 8)
	if min_x > max_x or min_z > max_z or min_y > max_y:
		return
	# Never open a cave into water.
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			for y in range(min_y, max_y + 2):
				if y < HEIGHT and blocks[index(x, y, z)] == water:
					return
	for x in range(min_x, max_x + 1):
		var fx := (x + cx * 16 + 0.5 - center.x) / radius
		for z in range(min_z, max_z + 1):
			var fz := (z + cz * 16 + 0.5 - center.z) / radius
			if fx * fx + fz * fz >= 1.0:
				continue
			for y in range(max_y, min_y - 1, -1):
				var fy := (y + 0.5 - center.y) / radius_y
				if fy > -0.7 and fx * fx + fy * fy + fz * fz < 1.0:
					var i := index(x, y, z)
					if blocks[i] != bedrock:
						blocks[i] = Blocks.AIR


## Step 5: ore veins and dirt / gravel pockets, only inside stone.
func _place_ores(blocks: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var stone: int = _id["stone"]
	for ore: Array in ORES:
		var id: int = _id[ore[0]]
		for vein in ore[1]:
			var start := Vector3(rng.randf() * 16.0, rng.randi_range(0, ore[3] - 1), rng.randf() * 16.0)
			_place_vein(blocks, rng, id, stone, ore[2], start)


## A vein: spheres along a short random line, like the classic ore veins.
func _place_vein(blocks: PackedByteArray, rng: RandomNumberGenerator, id: int, stone: int, size: int, start: Vector3) -> void:
	var angle := rng.randf() * PI
	var half := Vector3(sin(angle), 0.0, cos(angle)) * size / 8.0
	var a := start + half + Vector3(0, rng.randi_range(0, 2) - 1, 0)
	var b := start - half + Vector3(0, rng.randi_range(0, 2) - 1, 0)
	for i in size + 1:
		var center := a.lerp(b, float(i) / size)
		var radius := ((sin(i * PI / size) + 1.0) * rng.randf() * size / 16.0 + 1.0) / 2.0
		for x in range(maxi(floori(center.x - radius), 0), mini(floori(center.x + radius), 15) + 1):
			for y in range(maxi(floori(center.y - radius), 1), mini(floori(center.y + radius), HEIGHT - 1) + 1):
				for z in range(maxi(floori(center.z - radius), 0), mini(floori(center.z + radius), 15) + 1):
					var d := Vector3(x + 0.5, y + 0.5, z + 0.5) - center
					if d.length_squared() < radius * radius:
						var j := index(x, y, z)
						if blocks[j] == stone:
							blocks[j] = id


## Step 6: trees. Kept 2 blocks away from the column edge so the leaves fit.
func _place_trees(blocks: PackedByteArray, cx: int, cz: int, biomes: Array[String], rng: RandomNumberGenerator) -> void:
	var biome_here: String = biomes[8 * 16 + 8]
	var count := int((_tree_noise.get_noise_2d(cx * 16 + 8, cz * 16 + 8) * 4.0 + rng.randf() * 4.0 + 4.0) / 3.0)
	count += BIOMES[biome_here].trees
	if rng.randi_range(0, 9) == 0:
		count += 1
	for t in maxi(count, 0):
		var x := rng.randi_range(2, 13)
		var z := rng.randi_range(2, 13)
		var y := _surface_y(blocks, x, z)
		if y < 0:
			continue
		var ground := blocks[index(x, y, z)]
		if ground != _id["grass_plains"] and ground != _id["grass_forest"] and ground != _id["grass_taiga"] \
				and ground != _id["grass_swamp"] and ground != _id["grass_savanna"] and ground != _id["snowy_grass"] \
				and ground != _id["dirt"]:
			continue
		match biomes[z * 16 + x]:
			"taiga":
				if rng.randi_range(0, 2) == 0:
					_pine(blocks, rng, x, y + 1, z)
				else:
					_spruce(blocks, rng, x, y + 1, z)
			"forest":
				if rng.randi_range(0, 4) == 0:
					_round_tree(blocks, rng, x, y + 1, z, _id["birch_log"], _id["birch_leaves"], 5)
				else:
					_round_tree(blocks, rng, x, y + 1, z, _id["oak_log"], _id["oak_leaves"], 4)
			_:
				_round_tree(blocks, rng, x, y + 1, z, _id["oak_log"], _id["oak_leaves"], 4)


func _surface_y(blocks: PackedByteArray, x: int, z: int) -> int:
	for y in range(HEIGHT - 1, 0, -1):
		if blocks[index(x, y, z)] != Blocks.AIR:
			return y
	return -1


func _set_if_air(blocks: PackedByteArray, x: int, y: int, z: int, id: int) -> void:
	if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 or y >= HEIGHT:
		return
	var i := index(x, y, z)
	if blocks[i] == Blocks.AIR:
		blocks[i] = id


func _trunk_fits(blocks: PackedByteArray, x: int, y: int, z: int, height: int) -> bool:
	if y + height + 2 >= HEIGHT:
		return false
	for dy in height:
		if blocks[index(x, y + dy, z)] != Blocks.AIR:
			return false
	return true


## Oak and birch: a trunk with two wide leaf layers and two narrow ones;
## corner leaves are randomly left out.
func _round_tree(blocks: PackedByteArray, rng: RandomNumberGenerator, x: int, y: int, z: int, log_id: int, leaves: int, min_height: int) -> void:
	var height := rng.randi_range(min_height, min_height + 2)
	if not _trunk_fits(blocks, x, y, z, height):
		return
	blocks[index(x, y - 1, z)] = _id["dirt"]
	for ly in range(y + height - 3, y + height + 1):
		var above_top := ly - (y + height)
		var radius := 1 - above_top / 2
		for lx in range(x - radius, x + radius + 1):
			for lz in range(z - radius, z + radius + 1):
				var corner := absi(lx - x) == radius and absi(lz - z) == radius
				if corner and (rng.randi_range(0, 1) == 0 or above_top == 0):
					continue
				_set_if_air(blocks, lx, ly, lz, leaves)
	for dy in height:
		blocks[index(x, y + dy, z)] = log_id


## Spruce: a cone of leaf rings that widen and narrow going down.
func _spruce(blocks: PackedByteArray, rng: RandomNumberGenerator, x: int, y: int, z: int) -> void:
	var height := rng.randi_range(6, 9)
	if not _trunk_fits(blocks, x, y, z, height):
		return
	var leaves: int = _id["spruce_leaves"]
	var bare := rng.randi_range(1, 2) # trunk without leaves at the bottom
	var radius := 0
	var max_radius := rng.randi_range(2, 3)
	for ly in range(y + height, y + bare - 1, -1):
		for lx in range(x - radius, x + radius + 1):
			for lz in range(z - radius, z + radius + 1):
				if radius > 0 and absi(lx - x) == radius and absi(lz - z) == radius:
					continue
				_set_if_air(blocks, lx, ly, lz, leaves)
		radius = 0 if radius >= max_radius else radius + 1
		if radius == 0 and ly < y + height - 1:
			radius = 1
	_set_if_air(blocks, x, y + height + 1, z, leaves)
	blocks[index(x, y - 1, z)] = _id["dirt"]
	for dy in height:
		blocks[index(x, y + dy, z)] = _id["spruce_log"]


## Pine: a tall bare trunk with a small cap of leaves.
func _pine(blocks: PackedByteArray, rng: RandomNumberGenerator, x: int, y: int, z: int) -> void:
	var height := rng.randi_range(7, 11)
	if not _trunk_fits(blocks, x, y, z, height):
		return
	var leaves: int = _id["spruce_leaves"]
	var cap := rng.randi_range(3, 4)
	for ly in range(y + height - cap, y + height + 1):
		var radius := 1 if ly < y + height - 1 else 0
		for lx in range(x - radius, x + radius + 1):
			for lz in range(z - radius, z + radius + 1):
				_set_if_air(blocks, lx, ly, lz, leaves)
	_set_if_air(blocks, x, y + height + 1, z, leaves)
	blocks[index(x, y - 1, z)] = _id["dirt"]
	for dy in height:
		blocks[index(x, y + dy, z)] = _id["spruce_log"]


## Ice on the sea surface of cold biomes.
func _freeze(blocks: PackedByteArray, biomes: Array[String]) -> void:
	var water: int = _id["water"]
	var ice: int = _id["ice"]
	var y := SEA_LEVEL - 1
	for z in 16:
		for x in 16:
			if BIOMES[biomes[z * 16 + x]].cold:
				var i := index(x, y, z)
				if blocks[i] == water and blocks[index(x, y + 1, z)] == Blocks.AIR:
					blocks[i] = ice
