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
## Noise magnitudes of the classic generator: its octave noises are sums
## whose amplitude doubles for every lower octave (16 octaves: up to 65535),
## divided by 512 for the limit noises and by 10 for the main noise. The
## noises here are normalized fBm (about -1..1), so they are scaled back:
## the limits swing widely and the main noise switches sharply between them,
## which gives the classic cliffs, overhangs and mountains.
const LIMIT_AMPLITUDE := 128.0  # 65535 / 512
const MAIN_AMPLITUDE := 25.5    # 255 / 10
const DEPTH_AMPLITUDE := 8.2    # 65535 / 8000
const SCALE_AMPLITUDE := 1023.0 # 10 octaves
## Climate is sampled every CLIMATE_STEP blocks and interpolated: smooth
## and 16 times fewer noise calls than per block column.
const CLIMATE_STEP := 4
## Classic-style grass and foliage colors by climate: cold, hot and dry,
## hot and wet (corners of the classic color maps).
const GRASS_COLD := Color("80b497")
const GRASS_DRY := Color("bfb755")
const GRASS_WET := Color("47cd33")
const FOLIAGE_COLD := Color("60a17b")
const FOLIAGE_DRY := Color("aea42a")
const FOLIAGE_WET := Color("1abf00")
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
## BIOMES as packed tables indexed by biome number (BIOME_NAMES order), so
## the per-block loops don't read dictionaries.
const BIOME_NAMES: Array[String] = [
	"tundra", "taiga", "swampland", "forest", "seasonal_forest",
	"rainforest", "savanna", "shrubland", "plains", "desert",
]
var _biome_top := PackedInt32Array()
var _biome_filler := PackedInt32Array()
var _biome_trees := PackedInt32Array()
var _biome_cold := PackedByteArray()
var _water := 0
var _lava := 0
var _bedrock := 0
## Patches of tall grass per column and biome, like the classic game.
const GRASS_PATCHES := {"plains": 10, "rainforest": 10, "forest": 2, "seasonal_forest": 2, "taiga": 1, "shrubland": 1, "savanna": 1, "swampland": 1}
## Below this height caves are filled with lava (the classic lava level).
const LAVA_LEVEL := 10


func _init(seed_value: int) -> void:
	super(seed_value)
	_setup(_min_noise, 1, 0.0052, 8)
	_setup(_max_noise, 2, 0.0052, 8)
	_setup(_main_noise, 3, 0.0167, 6)
	_setup(_depth_noise, 4, 0.0015, 6)
	_setup(_scale_noise, 5, 0.0011, 4)
	# Large climate zones: biomes several hundred blocks across.
	_setup(_temperature_noise, 6, 0.0016, 4)
	_setup(_humidity_noise, 7, 0.0024, 4)
	_setup(_detail_noise, 8, 0.12, 2)
	_setup(_sand_noise, 9, 0.03, 3)
	_setup(_gravel_noise, 10, 0.03, 3)
	_setup(_soil_noise, 11, 0.06, 3)
	_setup(_tree_noise, 12, 0.02, 2)
	for block in Blocks.types:
		_id[block.name] = block.id
	for biome_name_key in BIOME_NAMES:
		var biome: Dictionary = BIOMES[biome_name_key]
		_biome_top.append(_id[biome.top])
		_biome_filler.append(_id[biome.filler])
		_biome_trees.append(biome.trees)
		_biome_cold.append(1 if biome.cold else 0)
	_water = _id["water"]
	_lava = _id["lava"]
	_bedrock = _id["bedrock"]


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


## Temperature (first 256) and humidity (next 256) of every block column of
## a chunk column, index x + 16 * z: sampled on a grid every CLIMATE_STEP
## blocks and interpolated, so biomes and colors change smoothly.
func climate(cx: int, cz: int) -> PackedFloat32Array:
	const CELLS := 16 / CLIMATE_STEP + 1
	var temps := PackedFloat32Array()
	var humids := PackedFloat32Array()
	temps.resize(CELLS * CELLS)
	humids.resize(CELLS * CELLS)
	for gz in CELLS:
		for gx in CELLS:
			var wx := cx * 16 + gx * CLIMATE_STEP
			var wz := cz * 16 + gz * CLIMATE_STEP
			temps[gx + gz * CELLS] = temperature(wx, wz)
			humids[gx + gz * CELLS] = humidity(wx, wz)
	var result := PackedFloat32Array()
	result.resize(512)
	for z in 16:
		var gz := z / CLIMATE_STEP
		var fz := float(z % CLIMATE_STEP) / CLIMATE_STEP
		for x in 16:
			var gx := x / CLIMATE_STEP
			var fx := float(x % CLIMATE_STEP) / CLIMATE_STEP
			var i00 := gx + gz * CELLS
			var t0 := temps[i00] + (temps[i00 + 1] - temps[i00]) * fx
			var t1 := temps[i00 + CELLS] + (temps[i00 + CELLS + 1] - temps[i00 + CELLS]) * fx
			var h0 := humids[i00] + (humids[i00 + 1] - humids[i00]) * fx
			var h1 := humids[i00 + CELLS] + (humids[i00 + CELLS + 1] - humids[i00 + CELLS]) * fx
			result[x + 16 * z] = t0 + (t1 - t0) * fz
			result[256 + x + 16 * z] = h0 + (h1 - h0) * fz
	return result


## Grass and foliage colors (linear) of every block column, like the
## classic color maps: from bluish green in the cold to yellow-green when
## hot and dry and lush green when hot and wet. Smooth across biomes.
func column_colors(cx: int, cz: int) -> Array[PackedColorArray]:
	var values := climate(cx, cz)
	var grass := PackedColorArray()
	var foliage := PackedColorArray()
	grass.resize(256)
	foliage.resize(256)
	for i in 256:
		var temp := values[i]
		var humid := values[256 + i]
		grass[i] = GRASS_COLD.lerp(GRASS_DRY.lerp(GRASS_WET, humid), temp).srgb_to_linear()
		foliage[i] = FOLIAGE_COLD.lerp(FOLIAGE_DRY.lerp(FOLIAGE_WET, humid), temp).srgb_to_linear()
	return [grass, foliage]


## The classic biome table.
static func biome_for(temp: float, humid: float) -> String:
	return BIOME_NAMES[biome_index(temp, humid)]


## Biome number (index in BIOME_NAMES).
static func biome_index(temp: float, humid: float) -> int:
	if temp < 0.1:
		return 0 # tundra
	humid *= temp
	if humid < 0.2:
		if temp < 0.5:
			return 0 # tundra
		return 6 if temp < 0.95 else 9 # savanna / desert
	if humid > 0.5 and temp < 0.7:
		return 2 # swampland
	if temp < 0.5:
		return 1 # taiga
	if temp < 0.97:
		return 7 if humid < 0.35 else 3 # shrubland / forest
	if humid < 0.45:
		return 8 # plains
	return 4 if humid < 0.9 else 5 # seasonal forest / rainforest


func biome_name(x: int, z: int) -> String:
	return biome_for(temperature(x, z), humidity(x, z))


# --- Generation --------------------------------------------------------------------

func generate_blocks(cx: int, cz: int) -> PackedInt32Array:
	var blocks := super(cx, cz)
	var climate_values := climate(cx, cz)
	var biomes := PackedByteArray()
	biomes.resize(256)
	for i in 256:
		biomes[i] = biome_index(climate_values[i], climate_values[256 + i])
	var top := _shape_terrain(blocks, cx, cz)
	_replace_surface(blocks, cx, cz, biomes, top)
	_carve_caves(blocks, cx, cz)
	var rng := column_rng(cx, cz, 100)
	_place_lava_lake(blocks, column_rng(cx, cz, 200))
	_place_ores(blocks, rng, top)
	_place_trees(blocks, cx, cz, biomes, rng)
	_place_plants(blocks, biomes, column_rng(cx, cz, 300))
	_place_clay(blocks, column_rng(cx, cz, 400))
	_freeze(blocks, biomes)
	return blocks


## Step 1: density field on a coarse grid, interpolated to blocks.
## Returns the highest stone block (used to skip ore veins in the air).
func _shape_terrain(blocks: PackedInt32Array, cx: int, cz: int) -> int:
	var stone: int = _id["stone"]
	var water: int = _id["water"]
	var top := -1
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

			var scale := (_scale_noise.get_noise_2d(wx, wz) * SCALE_AMPLITUDE + 256.0) / 512.0 * vegetation
			if scale > 1.0:
				scale = 1.0
			var depth := _depth_noise.get_noise_2d(wx, wz) * DEPTH_AMPLITUDE
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
				var mix := (_main_noise.get_noise_3d(wx, wy * 0.25, wz) * MAIN_AMPLITUDE + 1.0) * 0.5
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
				# Lerps written out (the same math as lerpf, without the calls).
				for sy in GRID_Y:
					var ty := sy / float(GRID_Y)
					var y := gy * GRID_Y + sy
					var a00 := d000 + (d010 - d000) * ty
					var a01 := d001 + (d011 - d001) * ty
					var a10 := d100 + (d110 - d100) * ty
					var a11 := d101 + (d111 - d101) * ty
					for sx in GRID_X:
						var tx := sx / float(GRID_X)
						var b0 := a00 + (a10 - a00) * tx
						var b1 := a01 + (a11 - a01) * tx
						var row := gx * GRID_X + sx + 16 * (gz * GRID_X + 16 * y)
						for sz in GRID_X:
							var value := b0 + (b1 - b0) * (sz / float(GRID_X))
							if value > 0.0:
								blocks[row + 16 * sz] = stone
								if y > top:
									top = y
							elif y < SEA_LEVEL:
								blocks[row + 16 * sz] = water
	return top


## Step 3: biome surface, beaches and bedrock, top-down per block column.
## `stone_top`: the highest stone; above it (and above the sea) is only air.
func _replace_surface(blocks: PackedInt32Array, cx: int, cz: int, biomes: PackedByteArray, stone_top: int) -> void:
	var start_y := mini(maxi(stone_top, SEA_LEVEL - 1), HEIGHT - 1)
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
			var biome := biomes[z * 16 + x]
			var biome_top := _biome_top[biome]
			var biome_filler := _biome_filler[biome]
			var sand_beach := _sand_noise.get_noise_2d(wx, wz) + rng.randf() * 0.2 > 0.0
			var gravel_beach := _gravel_noise.get_noise_2d(wz, wx) * 15.0 + rng.randf() * 0.2 > 3.0
			var soil_depth := int(_soil_noise.get_noise_2d(wx, wz) * 5.0 + 3.0 + rng.randf() * 0.25)
			var top := biome_top
			var filler := biome_filler
			var depth_left := -1
			# Uneven bedrock floor: layer y (0..4) is bedrock with chance (5 - y) / 5.
			var bedrock_mask := 1
			for y in range(1, 5):
				if rng.randi_range(0, 4) >= y:
					bedrock_mask |= 1 << y
			for y in range(start_y, -1, -1):
				var i := x + 16 * (z + 16 * y)
				if y <= 4 and (bedrock_mask >> y) & 1 == 1:
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
						top = biome_top
						filler = biome_filler
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
func _carve_caves(blocks: PackedInt32Array, cx: int, cz: int) -> void:
	for ox in range(-CAVE_RANGE, CAVE_RANGE + 1):
		for oz in range(-CAVE_RANGE, CAVE_RANGE + 1):
			# Only 1 column in 15 starts caves: decide that with an inline hash
			# before paying for a random generator.
			var h := world_seed * 6364136223846793005 + (cx + ox) * 1442695040888963407 + (cz + oz) * 3935559000370003845
			h ^= h >> 29
			h *= -4658895280553007687
			h ^= h >> 32
			if (h & 0xFFFFFF) % 15 != 0:
				continue
			var rng := column_rng(cx + ox, cz + oz, 2)
			var count := rng.randi_range(0, rng.randi_range(0, rng.randi_range(0, 39) + 1))
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
func _carve_tunnel(blocks: PackedInt32Array, cx: int, cz: int, seed_value: int, pos: Vector3,
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
	# A tunnel moves 1 block per step: skip it when even its full remaining
	# length can't bring it close enough to carve this column.
	var start_dx := pos.x - center_x
	var start_dz := pos.z - center_z
	if sqrt(start_dx * start_dx + start_dz * start_dz) - (length - step) > 8.0 + 2.0 * (1.5 + width) + 2.0:
		return
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


func _carve_ellipsoid(blocks: PackedInt32Array, cx: int, cz: int, center: Vector3, radius: float, radius_y: float) -> void:
	var water := _water
	var bedrock := _bedrock
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
				if y < HEIGHT and blocks[x + 16 * (z + 16 * y)] == water:
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
					var i := x + 16 * (z + 16 * y)
					if blocks[i] != bedrock:
						# Deep caves fill with lava, like the classic game.
						blocks[i] = _lava if y < LAVA_LEVEL else Blocks.AIR


## Step 5: ore veins and dirt / gravel pockets, only inside stone.
## `top`: the highest stone in the column; spheres above it only meet air
## and are skipped (their random numbers are still drawn, so the result is
## the same).
func _place_ores(blocks: PackedInt32Array, rng: RandomNumberGenerator, top: int) -> void:
	var stone: int = _id["stone"]
	for ore: Array in ORES:
		var id: int = _id[ore[0]]
		for vein in ore[1]:
			var start := Vector3(rng.randf() * 16.0, rng.randi_range(0, ore[3] - 1), rng.randf() * 16.0)
			_place_vein(blocks, rng, id, stone, ore[2], start, top)


## A vein: spheres along a short random line, like the classic ore veins.
func _place_vein(blocks: PackedInt32Array, rng: RandomNumberGenerator, id: int, stone: int, size: int, start: Vector3, top: int) -> void:
	var angle := rng.randf() * PI
	var half := Vector3(sin(angle), 0.0, cos(angle)) * size / 8.0
	var a := start + half + Vector3(0, rng.randi_range(0, 2) - 1, 0)
	var b := start - half + Vector3(0, rng.randi_range(0, 2) - 1, 0)
	for i in size + 1:
		var center := a.lerp(b, float(i) / size)
		var radius := ((sin(i * PI / size) + 1.0) * rng.randf() * size / 16.0 + 1.0) / 2.0
		var radius_squared := radius * radius
		var x0 := maxi(floori(center.x - radius), 0)
		var x1 := mini(floori(center.x + radius), 15)
		var y0 := maxi(floori(center.y - radius), 1)
		var y1 := mini(floori(center.y + radius), HEIGHT - 1)
		var z0 := maxi(floori(center.z - radius), 0)
		var z1 := mini(floori(center.z + radius), 15)
		if y0 > top:
			continue
		for y in range(y0, mini(y1, top) + 1):
			var dy := y + 0.5 - center.y
			for z in range(z0, z1 + 1):
				var dz := z + 0.5 - center.z
				if dy * dy + dz * dz >= radius_squared:
					continue # this row is outside the sphere
				var row := 16 * (z + 16 * y)
				for x in range(x0, x1 + 1):
					var dx := x + 0.5 - center.x
					if dx * dx + dy * dy + dz * dz < radius_squared:
						var j := row + x
						if blocks[j] == stone:
							blocks[j] = id


## Step 6: trees. Kept 2 blocks away from the column edge so the leaves fit.
func _place_trees(blocks: PackedInt32Array, cx: int, cz: int, biomes: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var biome_here := biomes[8 * 16 + 8]
	var count := int((_tree_noise.get_noise_2d(cx * 16 + 8, cz * 16 + 8) * 4.0 + rng.randf() * 4.0 + 4.0) / 3.0)
	count += _biome_trees[biome_here]
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
		match BIOME_NAMES[biomes[z * 16 + x]]:
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


## Lava lakes like the classic game: one column in 8 may get one, mostly
## deep underground (above sea level only one in 10). A few overlapping
## blobs; the lower half fills with lava, the upper half is air.
func _place_lava_lake(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	if rng.randi_range(0, 7) != 0:
		return
	var y := rng.randi_range(0, rng.randi_range(0, 119) + 7)
	if y >= SEA_LEVEL and rng.randi_range(0, 9) != 0:
		return
	var floor_y := y - 4
	if floor_y < 2:
		return
	var shape := PackedByteArray()
	shape.resize(16 * 16 * 8)
	for blob in rng.randi_range(4, 7):
		var size := Vector3(rng.randf() * 6.0 + 3.0, rng.randf() * 4.0 + 2.0, rng.randf() * 6.0 + 3.0)
		var center := Vector3(rng.randf() * (16.0 - size.x - 2.0) + 1.0 + size.x / 2.0,
			rng.randf() * (8.0 - size.y - 4.0) + 2.0 + size.y / 2.0,
			rng.randf() * (16.0 - size.z - 2.0) + 1.0 + size.z / 2.0)
		for lx in range(1, 15):
			for lz in range(1, 15):
				for ly in range(1, 7):
					var d := (Vector3(lx, ly, lz) + Vector3(0.5, 0.5, 0.5) - center) / (size / 2.0)
					if d.length_squared() < 1.0:
						shape[lx + 16 * (lz + 16 * ly)] = 1
	# Not into water or open air: the classic game skips such spots.
	for i in shape.size():
		if shape[i] == 0:
			continue
		var ly := i / 256
		var block := blocks[index(i % 16, floor_y + ly, (i / 16) % 16)]
		if block == _water or (ly < 4 and block == Blocks.AIR):
			return
	for i in shape.size():
		if shape[i] == 1:
			var ly := i / 256
			var j := index(i % 16, floor_y + ly, (i / 16) % 16)
			if blocks[j] != _bedrock:
				blocks[j] = _lava if ly < 4 else Blocks.AIR


## Tall grass, ferns, flowers, dead bushes and pumpkins like the classic game: patches
## around random spots (grass per biome, rainforests mostly ferns), two
## patches of dandelions and sometimes roses everywhere, dead bushes in
## deserts. Only on ground they can grow on, inside this column.
func _place_plants(blocks: PackedInt32Array, biomes: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var biome := BIOME_NAMES[biomes[8 * 16 + 8]]
	for patch in GRASS_PATCHES.get(biome, 0):
		var plant: int = _id["fern"] if biome == "rainforest" and rng.randi_range(0, 2) != 0 else _id["tall_grass"]
		_plant_patch(blocks, rng, plant, 128)
	for patch in 2:
		_plant_patch(blocks, rng, _id["dandelion"], 64)
	if rng.randi_range(0, 1) == 0:
		_plant_patch(blocks, rng, _id["rose"], 64)
	if biome == "desert":
		for patch in 2:
			_plant_patch(blocks, rng, _id["dead_bush"], 4)
	# Pumpkins: one column in 32 gets a patch, facing every way, on grass.
	if rng.randi_range(0, 31) == 0:
		var x0 := rng.randi_range(0, 15)
		var z0 := rng.randi_range(0, 15)
		var y0 := _surface_y(blocks, x0, z0) + 1
		for t in 64:
			var x := x0 + rng.randi_range(0, 7) - rng.randi_range(0, 7)
			var y := y0 + rng.randi_range(0, 3) - rng.randi_range(0, 3)
			var z := z0 + rng.randi_range(0, 7) - rng.randi_range(0, 7)
			if x < 0 or x > 15 or z < 0 or z > 15 or y < 1 or y >= HEIGHT:
				continue
			if blocks[index(x, y, z)] == Blocks.AIR and Blocks.get_type(blocks[index(x, y - 1, z)]).name.begins_with("grass_"):
				blocks[index(x, y, z)] = Blocks.variant("pumpkin", rng.randi_range(0, 3))


func _plant_patch(blocks: PackedInt32Array, rng: RandomNumberGenerator, plant: int, tries: int) -> void:
	var x0 := rng.randi_range(0, 15)
	var z0 := rng.randi_range(0, 15)
	var y0 := _surface_y(blocks, x0, z0) + 1
	if y0 <= 0:
		return
	for t in tries:
		var x := x0 + rng.randi_range(0, 7) - rng.randi_range(0, 7)
		var y := y0 + rng.randi_range(0, 3) - rng.randi_range(0, 3)
		var z := z0 + rng.randi_range(0, 7) - rng.randi_range(0, 7)
		if x < 0 or x > 15 or z < 0 or z > 15 or y < 1 or y >= HEIGHT:
			continue
		if blocks[index(x, y, z)] == Blocks.AIR and PlantBehavior.can_stay(plant, blocks[index(x, y - 1, z)]):
			blocks[index(x, y, z)] = plant


func _surface_y(blocks: PackedInt32Array, x: int, z: int) -> int:
	for y in range(HEIGHT - 1, 0, -1):
		if blocks[index(x, y, z)] != Blocks.AIR:
			return y
	return -1


func _set_if_air(blocks: PackedInt32Array, x: int, y: int, z: int, id: int) -> void:
	if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 or y >= HEIGHT:
		return
	var i := index(x, y, z)
	if blocks[i] == Blocks.AIR:
		blocks[i] = id


func _trunk_fits(blocks: PackedInt32Array, x: int, y: int, z: int, height: int) -> bool:
	if y + height + 2 >= HEIGHT:
		return false
	for dy in height:
		if blocks[index(x, y + dy, z)] != Blocks.AIR:
			return false
	return true


## Oak and birch: a trunk with two wide leaf layers and two narrow ones;
## corner leaves are randomly left out.
func _round_tree(blocks: PackedInt32Array, rng: RandomNumberGenerator, x: int, y: int, z: int, log_id: int, leaves: int, min_height: int) -> void:
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
func _spruce(blocks: PackedInt32Array, rng: RandomNumberGenerator, x: int, y: int, z: int) -> void:
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
func _pine(blocks: PackedInt32Array, rng: RandomNumberGenerator, x: int, y: int, z: int) -> void:
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


## Clay like the classic game: a few small patches on the sand and dirt at
## the bottom of shallow water.
func _place_clay(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var clay: int = _id["clay"]
	for patch in 3:
		var x0 := rng.randi_range(2, 13)
		var z0 := rng.randi_range(2, 13)
		var y := _surface_y(blocks, x0, z0)
		while y > 0 and blocks[index(x0, y, z0)] == _water:
			y -= 1
		if y >= SEA_LEVEL - 1 or blocks[index(x0, y + 1, z0)] != _water:
			continue
		var radius := rng.randi_range(1, 2)
		for x in range(x0 - radius, x0 + radius + 1):
			for z in range(z0 - radius, z0 + radius + 1):
				if (x - x0) * (x - x0) + (z - z0) * (z - z0) > radius * radius + 1:
					continue
				for dy in range(-1, 1):
					var i := index(x, y + dy, z)
					var here := blocks[i]
					if here == _id["sand"] or here == _id["dirt"] or here == _id["gravel"]:
						blocks[i] = clay


## Ice on the sea surface of cold biomes; snow lying on the land and trees.
func _freeze(blocks: PackedInt32Array, biomes: PackedByteArray) -> void:
	var water: int = _id["water"]
	var ice: int = _id["ice"]
	var y := SEA_LEVEL - 1
	for z in 16:
		for x in 16:
			if _biome_cold[biomes[z * 16 + x]] == 1:
				var i := index(x, y, z)
				if blocks[i] == water and blocks[index(x, y + 1, z)] == Blocks.AIR:
					blocks[i] = ice
				# A snow layer on the highest block, if it can hold one.
				var top := _surface_y(blocks, x, z)
				if top > 0 and top < HEIGHT - 1:
					var under := blocks[index(x, top, z)]
					if Blocks.is_opaque_table[under] == 1 or Blocks.get_type(under).name.ends_with("_leaves"):
						blocks[index(x, top + 1, z)] = _id["snow_layer"]
