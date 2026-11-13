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
##    empty space is water.
##
## World types (WorldSave.layout, set_layout):
## - classic: like Beta 1.7.3, 128 high with the sea at 64;
## - tall ("Tall Mountains"): the same land, 256 high, the sea at 64 and
##   mountains rising far above (softer slopes above the middle);
## - old worlds made 256 high with the sea at 128: the classic part (128,
##   or 192 for higher mountains) put 64 blocks up (LEGACY_SHIFT) on a deep
##   layer of its own: stone with caves (lava at the bottom), lava lakes,
##   dungeons, ores at the classic heights and the bedrock floor.
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
var _dungeon_ids := {}
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
## The classic generator's own column: its sea level and height (192 in
## new worlds: "tall" mountains), and its grid height in cells at 128.
const SEA := 64
const UPPER_HEIGHT := 128
const TALL_UPPER_HEIGHT := 192
const LEGACY_CELLS := 16
## Ores of the deep layer (WorldGenerator.LEGACY_SHIFT blocks): the classic
## heights from the bottom of the world.
const DEEP_ORES := [
	["dirt", 10, 32, 64],
	["gravel", 5, 32, 64],
	["coal_ore", 10, 16, 64],
	["iron_ore", 20, 8, 64],
	["gold_ore", 2, 8, 32],
	["redstone_ore", 8, 7, 16],
	["diamond_ore", 1, 7, 16],
	["lapis_ore", 1, 6, 32],
]
## In new worlds the deep ores (gold, redstone, diamonds, lapis) are only in
## the deep layer; worlds from before keep the classic ones up there too.
const UPPER_ORES := ["dirt", "gravel", "coal_ore", "iron_ore"]

## New worlds: mountains rise about twice as high (worlds from before the
## world was 256 high keep the classic shape so they join without seams).
var tall := true
var _h := TALL_UPPER_HEIGHT
var _shift := LEGACY_SHIFT
var _deep := true
var _cells := TALL_UPPER_HEIGHT / GRID_Y
## The same generator in native code (NativeBetaGenerator,
## native/src/native_beta_generator.cpp): block for block the same columns,
## many times faster. Null without the native library (then the GDScript
## below generates).
var _native: Object


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
	_dungeon_ids = {"cobble": _id["cobblestone"], "mossy": _id["mossy_cobblestone"], "chest": _id["dungeon_chest"]}
	for mob: String in DungeonBehavior.SPAWNER_TYPES:
		_dungeon_ids["spawner_" + mob] = _id["mob_spawner_" + mob]
	for biome_name_key in BIOME_NAMES:
		var biome: Dictionary = BIOMES[biome_name_key]
		_biome_top.append(_id[biome.top])
		_biome_filler.append(_id[biome.filler])
		_biome_trees.append(biome.trees)
		_biome_cold.append(1 if biome.cold else 0)
	_water = _id["water"]
	_lava = _id["lava"]
	_bedrock = _id["bedrock"]
	_setup_native()
	set_layout(WorldSave.layout_of(WorldSave.CLASSIC)) # (set_layout for the others)
	if _grass_map.is_empty() and OS.get_thread_caller_id() == OS.get_main_thread_id():
		load_color_maps()


## Hands the noises, block ids and tables to the native generator.
func _setup_native() -> void:
	if not ClassDB.class_exists("NativeBetaGenerator"):
		return
	var grass_named := PackedByteArray()
	var leaves := PackedByteArray()
	for block in Blocks.types:
		grass_named.append(1 if block.name.begins_with("grass_") else 0)
		leaves.append(1 if block.name.ends_with("_leaves") else 0)
	var pumpkins := PackedInt32Array()
	for id: int in Blocks.family_ids("pumpkin"):
		pumpkins.append(id)
	_native = ClassDB.instantiate("NativeBetaGenerator")
	_native.call("setup", {
		"seed": world_seed, "tall": tall, "ids": _id, "pumpkins": pumpkins,
		"noises": [_min_noise, _max_noise, _main_noise, _depth_noise, _scale_noise, _temperature_noise,
			_humidity_noise, _detail_noise, _sand_noise, _gravel_noise, _soil_noise, _tree_noise],
		"collides": Blocks.collides_table, "liquid": Blocks.liquid_table, "opaque": Blocks.is_opaque_table,
		"grass_named": grass_named, "leaves": leaves,
	})


## Worlds made before the world was 256 high (converted ones) keep the
## classic terrain shape. Call before generating.
func set_tall(value: bool) -> void:
	set_layout({"shift": LEGACY_SHIFT, "deep": true, "upper": TALL_UPPER_HEIGHT if value else UPPER_HEIGHT, "tall": value})


## The world's layout (WorldSave.layout): the classic part "upper" high from
## y "shift" up, softer mountains above the middle ("tall"), the deep layer
## under it ("deep"). Call before generating.
func set_layout(layout: Dictionary) -> void:
	tall = layout.get("tall", false)
	_shift = layout.get("shift", 0)
	_deep = layout.get("deep", false)
	legacy_shift = _shift
	_h = clampi(int(layout.get("upper", UPPER_HEIGHT)) / GRID_Y * GRID_Y, UPPER_HEIGHT, HEIGHT - _shift)
	_cells = _h / GRID_Y
	if _native:
		_native.call("set_layout", _shift, _deep, _h, tall)


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
## Grass and foliage colors like Beta's: looked up in misc/grasscolor.png and
## misc/foliagecolor.png (256 x 256; a texture pack's too) at x = (1 -
## temperature) * 255, y = (1 - humidity * temperature) * 255. The game's
## own maps hold the colors of color_formula().
static var _grass_map := PackedByteArray()
static var _foliage_map := PackedByteArray()


## Loads the color maps (on the main thread, before columns are generated).
static func load_color_maps() -> void:
	for pair: Array in [["grasscolor", "_grass_map"], ["foliagecolor", "_foliage_map"]]:
		var image := TexturePacks.load_image("res://assets/textures/misc/%s.png" % pair[0])
		if image.get_size() != Vector2i(256, 256):
			image.resize(256, 256, Image.INTERPOLATE_NEAREST)
		if pair[1] == "_grass_map":
			_grass_map = image.get_data()
		else:
			_foliage_map = image.get_data()


## The color between the corners (the game's maps are made from it).
static func color_formula(temp: float, humid: float, foliage: bool) -> Color:
	if foliage:
		return FOLIAGE_COLD.lerp(FOLIAGE_DRY.lerp(FOLIAGE_WET, humid), temp)
	return GRASS_COLD.lerp(GRASS_DRY.lerp(GRASS_WET, humid), temp)


static func _map_color(map: PackedByteArray, temp: float, humid: float) -> Color:
	var x := clampi(int((1.0 - temp) * 255.0), 0, 255)
	var y := clampi(int((1.0 - humid * temp) * 255.0), 0, 255)
	var i := (x + y * 256) * 4
	return Color8(map[i], map[i + 1], map[i + 2])


func column_colors(cx: int, cz: int) -> Array[PackedColorArray]:
	if _grass_map.is_empty():
		load_color_maps()
	var values := climate(cx, cz)
	var grass := PackedColorArray()
	var foliage := PackedColorArray()
	grass.resize(256)
	foliage.resize(256)
	for i in 256:
		var temp := values[i]
		var humid := values[256 + i]
		grass[i] = _map_color(_grass_map, temp, humid).srgb_to_linear()
		foliage[i] = _map_color(_foliage_map, temp, humid).srgb_to_linear()
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
	if _native:
		return _native.call("generate_blocks", cx, cz)
	return generate_blocks_script(cx, cz)


## The GDScript generator (without the native library; tests compare the two).
func generate_blocks_script(cx: int, cz: int) -> PackedInt32Array:
	var upper := PackedInt32Array()
	upper.resize(16 * 16 * _h)
	_generate_upper(upper, cx, cz)
	# The world column: the deep layer's stone, the upper part, air above.
	var blocks := PackedInt32Array()
	blocks.resize(_shift * 256)
	blocks.fill(_id["stone"])
	blocks.append_array(upper)
	blocks.resize(COLUMN_VOLUME)
	_place_floor(blocks, cx, cz)
	if _deep:
		_generate_deep(blocks, cx, cz)
	return blocks


## The bedrock floor, uneven like the game's: y 0 and up to 4 above.
func _place_floor(blocks: PackedInt32Array, cx: int, cz: int) -> void:
	var rng := column_rng(cx, cz, 700)
	for i in 256:
		blocks[i] = _bedrock
		for y in range(1, 5):
			if rng.randi_range(0, 4) >= y:
				blocks[i + 256 * y] = _bedrock


## The deep layer under the classic part (on the bedrock floor): caves (lava below
## y 10), a lava lake now and then, dungeons and ores.
func _generate_deep(blocks: PackedInt32Array, cx: int, cz: int) -> void:
	# New worlds: deep caves reach up into the classic part; converted worlds
	# keep them under the old floor (their old lava and water stay put).
	_carve_caves(blocks, cx, cz, 702, LEGACY_SHIFT - 8, LEGACY_SHIFT + 12 if tall else LEGACY_SHIFT - 2, LAVA_LEVEL)
	var lakes := column_rng(cx, cz, 703)
	if lakes.randi_range(0, 3) == 0:
		_place_lake(blocks, lakes, lakes.randi_range(10, LEGACY_SHIFT - 8), _lava)
	DungeonBehavior.place(blocks, column_rng(cx, cz, 704), LEGACY_SHIFT + 16, _dungeon_ids)
	_place_ores(blocks, column_rng(cx, cz, 705), LEGACY_SHIFT + 8, DEEP_ORES)


## The classic generator's column (16 x _h x 16, sea at 64).
func _generate_upper(blocks: PackedInt32Array, cx: int, cz: int) -> void:
	var climate_values := climate(cx, cz)
	var biomes := PackedByteArray()
	biomes.resize(256)
	for i in 256:
		biomes[i] = biome_index(climate_values[i], climate_values[256 + i])
	var top := _shape_terrain(blocks, cx, cz)
	_replace_surface(blocks, cx, cz, biomes, top)
	_carve_caves(blocks, cx, cz, 2, 119, _h - 8, -1)
	var rng := column_rng(cx, cz, 100)
	_place_water_lake(blocks, column_rng(cx, cz, 250))
	_place_lava_lake(blocks, column_rng(cx, cz, 200))
	DungeonBehavior.place(blocks, column_rng(cx, cz, 600), _h, _dungeon_ids)
	_place_ores(blocks, rng, top, ORES, [] as Array if not tall else UPPER_ORES)
	_place_trees(blocks, cx, cz, biomes, rng)
	_place_plants(blocks, biomes, column_rng(cx, cz, 300))
	_place_clay(blocks, column_rng(cx, cz, 400))
	var nature := column_rng(cx, cz, 500)
	_place_cacti(blocks, biomes, nature)
	_place_sugar_cane(blocks, nature)
	_place_mushrooms(blocks, nature)
	_place_springs(blocks, nature)
	_freeze(blocks, biomes)


## Step 1: density field on a coarse grid, interpolated to blocks.
## Returns the highest stone block (used to skip ore veins in the air).
func _shape_terrain(blocks: PackedInt32Array, cx: int, cz: int) -> int:
	var stone: int = _id["stone"]
	var water: int = _id["water"]
	var top := -1
	var stride_y := _cells + 1
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
			depth = depth * LEGACY_CELLS / 16.0
			var center := LEGACY_CELLS / 2.0 + 0.5 + depth * 4.0

			for gy in stride_y:
				var wy := float(gy * GRID_Y)
				var rise := gy - center
				if tall and rise > 1.0:
					rise = 1.0 + (rise - 1.0) * 0.3 # new worlds: hills about twice as high, mountains higher still
				var offset := rise * 12.0 / scale
				if offset < 0.0:
					offset *= 4.0
				var low := _min_noise.get_noise_3d(wx, wy * 0.5, wz) * LIMIT_AMPLITUDE
				var high := _max_noise.get_noise_3d(wx, wy * 0.5, wz) * LIMIT_AMPLITUDE
				var mix := (_main_noise.get_noise_3d(wx, wy * 0.25, wz) * MAIN_AMPLITUDE + 1.0) * 0.5
				var value := low if mix < 0.0 else (high if mix > 1.0 else lerpf(low, high, mix))
				value -= offset
				if gy > _cells - 3:
					var fade := (gy - (_cells - 3)) / 3.0
					value = value * (1.0 - fade) - 10.0 * fade
				density[gx * stride_z + gz * stride_y + gy] = value

	# Trilinear interpolation inside every cell.
	for gx in CELLS_X:
		for gz in CELLS_X:
			for gy in _cells:
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
							elif y < SEA:
								blocks[row + 16 * sz] = water
	return top


## Step 3: biome surface, beaches and bedrock, top-down per block column.
## `stone_top`: the highest stone; above it (and above the sea) is only air.
func _replace_surface(blocks: PackedInt32Array, cx: int, cz: int, biomes: PackedByteArray, stone_top: int) -> void:
	var start_y := mini(maxi(stone_top, SEA - 1), _h - 1)
	var rng := column_rng(cx, cz, 1)
	var stone: int = _id["stone"]
	var water: int = _id["water"]
	var sand: int = _id["sand"]
	var gravel: int = _id["gravel"]
	var sandstone: int = _id["sandstone"]
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
					continue # the classic bedrock floor: now the deep layer's stone
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
					elif y >= SEA - 4 and y <= SEA + 1:
						top = biome_top
						filler = biome_filler
						if gravel_beach:
							top = Blocks.AIR
							filler = gravel
						if sand_beach:
							top = sand
							filler = sand
					if y < SEA and top == Blocks.AIR:
						top = water
					depth_left = soil_depth
					blocks[i] = top if y >= SEA - 1 else filler
				elif depth_left > 0:
					depth_left -= 1
					blocks[i] = filler
					if depth_left == 0 and filler == sand:
						depth_left = rng.randi_range(0, 3)
						filler = sandstone


## Step 4: worm caves from this and nearby columns, carved where they pass
## through this column.
## `salt` picks the random numbers, caves start below `start_span` + 8,
## reach up to `max_y`; below `lava_level` they fill with lava.
func _carve_caves(blocks: PackedInt32Array, cx: int, cz: int, salt: int, start_span: int, max_y: int, lava_level: int) -> void:
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
			var rng := column_rng(cx + ox, cz + oz, salt)
			var count := rng.randi_range(0, rng.randi_range(0, rng.randi_range(0, 39) + 1))
			for i in count:
				var start := Vector3(
					(cx + ox) * 16 + rng.randi_range(0, 15),
					rng.randi_range(0, rng.randi_range(0, start_span) + 8),
					(cz + oz) * 16 + rng.randi_range(0, 15))
				var tunnels := 1
				if rng.randi_range(0, 3) == 0:
					_carve_tunnel(blocks, cx, cz, rng.randi(), start, 1.0 + rng.randf() * 6.0, 0.0, 0.0, -1, -1, 0.5, max_y, lava_level)
					tunnels += rng.randi_range(0, 3)
				for t in tunnels:
					var yaw := rng.randf() * TAU
					var pitch := (rng.randf() - 0.5) * 2.0 / 8.0
					var width := rng.randf() * 2.0 + rng.randf()
					if rng.randi_range(0, 9) == 0:
						width *= rng.randf() * rng.randf() * 3.0 + 1.0
					_carve_tunnel(blocks, cx, cz, rng.randi(), start, width, yaw, pitch, 0, 0, 1.0, max_y, lava_level)


## One tunnel (or a room if step == -1): a random walk that carves
## ellipsoids. May split into two branches.
func _carve_tunnel(blocks: PackedInt32Array, cx: int, cz: int, seed_value: int, pos: Vector3,
		width: float, yaw: float, pitch: float, step: int, length: int, height_ratio: float, max_y: int, lava_level: int) -> void:
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
			_carve_tunnel(blocks, cx, cz, rng.randi(), pos, rng.randf() * 0.5 + 0.5, yaw - PI / 2.0, pitch / 3.0, step, length, 1.0, max_y, lava_level)
			_carve_tunnel(blocks, cx, cz, rng.randi(), pos, rng.randf() * 0.5 + 0.5, yaw + PI / 2.0, pitch / 3.0, step, length, 1.0, max_y, lava_level)
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
		_carve_ellipsoid(blocks, cx, cz, pos, radius, radius_y, max_y, lava_level)
		if is_room:
			return


func _carve_ellipsoid(blocks: PackedInt32Array, cx: int, cz: int, center: Vector3, radius: float, radius_y: float,
		top_y: int, lava_level: int) -> void:
	var water := _water
	var bedrock := _bedrock
	var min_x := maxi(floori(center.x - radius) - cx * 16 - 1, 0)
	var max_x := mini(floori(center.x + radius) - cx * 16 + 1, 15)
	var min_z := maxi(floori(center.z - radius) - cz * 16 - 1, 0)
	var max_z := mini(floori(center.z + radius) - cz * 16 + 1, 15)
	var min_y := maxi(floori(center.y - radius_y) - 1, 1)
	var max_y := mini(floori(center.y + radius_y) + 1, top_y)
	if min_x > max_x or min_z > max_z or min_y > max_y:
		return
	# Never open a cave into water.
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			for y in range(min_y, max_y + 2):
				var j := x + 16 * (z + 16 * y)
				if j < blocks.size() and blocks[j] == water:
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
						blocks[i] = _lava if y < lava_level else Blocks.AIR


## Step 5: ore veins and dirt / gravel pockets, only inside stone.
## `top`: the highest stone in the column; spheres above it only meet air
## and are skipped (their random numbers are still drawn, so the result is
## the same).
## `only`: the ores placed (all when empty; the others still draw their
## random numbers).
func _place_ores(blocks: PackedInt32Array, rng: RandomNumberGenerator, top: int, ores: Array, only: Array = []) -> void:
	var stone: int = _id["stone"]
	for ore: Array in ores:
		var id: int = _id[ore[0]] if only.is_empty() or only.has(ore[0]) else stone
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
		var y1 := mini(floori(center.y + radius), blocks.size() / 256 - 1)
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


## Step 6: trees like Beta 1.7.3's (TreeShapes): forests, rainforests,
## seasonal forests and taiga get a number from the tree noise (plus 5, or 2
## in seasonal forests), every biome one more now and then, deserts, tundra
## and plains none. The kind by biome: taiga pines (1 in 3) and spruces;
## forests birches (1 in 5), big oaks (1 in 3 of the rest) and oaks;
## rainforests big oaks (1 in 3) and oaks; elsewhere big oaks (1 in 10) and
## oaks. Each in its column: bigger kinds stand further from its edges so
## their leaves fit.
func _place_trees(blocks: PackedInt32Array, cx: int, cz: int, biomes: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var biome_here := biomes[8 * 16 + 8]
	var noise_count := int((_tree_noise.get_noise_2d(cx * 16 + 8, cz * 16 + 8) * 4.0 + rng.randf() * 4.0 + 4.0) / 3.0)
	var count := 0
	if rng.randi_range(0, 9) == 0:
		count += 1
	var extra: int = _biome_trees[biome_here]
	count += extra + (noise_count if extra > 0 else 0)
	var canvas := TreeShapes.ColumnCanvas.new(blocks, _h)
	for t in maxi(count, 0):
		var x := rng.randi_range(2, 13)
		var z := rng.randi_range(2, 13)
		var kind := _tree_kind(BIOME_NAMES[biome_here], rng)
		var margin: int = TREE_MARGINS[kind]
		x = clampi(x, margin, 15 - margin)
		z = clampi(z, margin, 15 - margin)
		var y := _surface_y(blocks, x, z)
		if y < 0 or not TreeShapes.is_ground(blocks[index(x, y, z)]):
			continue
		match kind:
			"oak":
				TreeShapes.oak(canvas, rng, x, y + 1, z, _id["oak_log"], _id["oak_leaves"], 4)
			"birch":
				TreeShapes.oak(canvas, rng, x, y + 1, z, _id["birch_log"], _id["birch_leaves"], 5)
			"spruce":
				TreeShapes.spruce(canvas, rng, x, y + 1, z)
			"pine":
				TreeShapes.pine(canvas, rng, x, y + 1, z)
			"big_oak":
				TreeShapes.big_oak(canvas, rng, x, y + 1, z)


## How far from the column's edge each kind's trunk stands (its leaves fit).
const TREE_MARGINS := {"oak": 2, "birch": 2, "spruce": 3, "pine": 4, "big_oak": 5}


## A tree kind for the biome, like Beta's getRandomWorldGenForTrees.
static func _tree_kind(biome: String, rng: RandomNumberGenerator) -> String:
	match biome:
		"taiga":
			return "pine" if rng.randi_range(0, 2) == 0 else "spruce"
		"forest":
			if rng.randi_range(0, 4) == 0:
				return "birch"
			return "big_oak" if rng.randi_range(0, 2) == 0 else "oak"
		"rainforest":
			return "big_oak" if rng.randi_range(0, 2) == 0 else "oak"
	return "big_oak" if rng.randi_range(0, 9) == 0 else "oak"


## Lava lakes like the classic game: one column in 8 may get one, mostly
## deep underground (above sea level only one in 10). A few overlapping
## blobs; the lower half fills with lava, the upper half is air.
func _place_lava_lake(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	if rng.randi_range(0, 7) != 0:
		return
	var y := rng.randi_range(0, rng.randi_range(0, 119) + 7)
	if y >= SEA and rng.randi_range(0, 9) != 0:
		return
	_place_lake(blocks, rng, y, _lava)


## Water lakes like the classic game: one column in 4, at any height (on
## the surface or underground).
func _place_water_lake(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	if rng.randi_range(0, 3) != 0:
		return
	_place_lake(blocks, rng, rng.randi_range(8, _h - 8), _water)


## A lake: a few overlapping blobs, the lower half filled with `liquid`, the
## upper half air; skipped where it would open into water or float over air.
func _place_lake(blocks: PackedInt32Array, rng: RandomNumberGenerator, y: int, liquid: int) -> void:
	var floor_y := y - 4
	if floor_y < 2 or floor_y + 8 >= _h:
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
		if block == _water or block == _lava or (ly < 4 and block == Blocks.AIR):
			return
	for i in shape.size():
		if shape[i] == 1:
			var ly := i / 256
			var j := index(i % 16, floor_y + ly, (i / 16) % 16)
			if blocks[j] != _bedrock:
				blocks[j] = liquid if ly < 4 else Blocks.AIR


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
			if x < 0 or x > 15 or z < 0 or z > 15 or y < 1 or y >= _h:
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
		if x < 0 or x > 15 or z < 0 or z > 15 or y < 1 or y >= _h:
			continue
		if blocks[index(x, y, z)] == Blocks.AIR and PlantBehavior.can_stay(plant, blocks[index(x, y - 1, z)]):
			blocks[index(x, y, z)] = plant


func _surface_y(blocks: PackedInt32Array, x: int, z: int) -> int:
	for y in range(_h - 1, 0, -1):
		if blocks[index(x, y, z)] != Blocks.AIR:
			return y
	return -1


## Clay like the classic game: a few small patches on the sand and dirt at
## the bottom of shallow water.
func _place_clay(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var clay: int = _id["clay"]
	for patch in 2:
		if rng.randi_range(0, 1) == 0:
			continue
		var x0 := rng.randi_range(2, 13)
		var z0 := rng.randi_range(2, 13)
		var y := _surface_y(blocks, x0, z0)
		while y > 0 and blocks[index(x0, y, z0)] == _water:
			y -= 1
		if y >= SEA - 1 or blocks[index(x0, y + 1, z0)] != _water:
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


## Cactus in deserts like the classic game: 10 tries per column, 1-3 high,
## on sand with nothing beside it.
func _place_cacti(blocks: PackedInt32Array, biomes: PackedByteArray, rng: RandomNumberGenerator) -> void:
	if BIOME_NAMES[biomes[8 * 16 + 8]] != "desert":
		return
	var cactus: int = _id["cactus"]
	for attempt in 10:
		var x := rng.randi_range(1, 14)
		var z := rng.randi_range(1, 14)
		var y := _surface_y(blocks, x, z) + 1
		var height := 1 + rng.randi_range(0, rng.randi_range(0, 2) + 1)
		if y <= 0 or blocks[index(x, y - 1, z)] != _id["sand"]:
			continue
		for h in mini(height, 3):
			var free := blocks[index(x, y + h, z)] == Blocks.AIR
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if blocks[index(x + offset.x, y + h, z + offset.y)] != Blocks.AIR:
					free = false
			if not free:
				break
			blocks[index(x, y + h, z)] = cactus


## Sugar cane like the classic game: 20 tries per column, 2-3 high, on grass,
## dirt or sand right next to water.
func _place_sugar_cane(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var reeds: int = _id["sugar_cane_block"]
	for attempt in 20:
		var x := rng.randi_range(1, 14)
		var z := rng.randi_range(1, 14)
		var y := _surface_y(blocks, x, z) + 1
		if y <= 0 or blocks[index(x, y, z)] != Blocks.AIR:
			continue
		var ground := Blocks.get_type(blocks[index(x, y - 1, z)]).name
		if not (ground.begins_with("grass_") or ground == "dirt" or ground == "sand"):
			continue
		var by_water := false
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if blocks[index(x + offset.x, y - 1, z + offset.y)] == _water:
				by_water = true
		if not by_water:
			continue
		var height := mini(2 + rng.randi_range(0, rng.randi_range(0, 2) + 1), 3)
		for h in height:
			if blocks[index(x, y + h, z)] == Blocks.AIR:
				blocks[index(x, y + h, z)] = reeds


## Mushrooms like the classic game: brown ones in one column of 4, red ones in
## one of 8, in patches on solid ground (mostly in caves: they need the dark).
func _place_mushrooms(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	for kind: Array in [["brown_mushroom", 4], ["red_mushroom", 8]]:
		if rng.randi_range(0, kind[1] - 1) != 0:
			continue
		var id: int = _id[kind[0]]
		var x0 := rng.randi_range(0, 15)
		var z0 := rng.randi_range(0, 15)
		var y0 := rng.randi_range(1, maxi(_surface_y(blocks, x0, z0), 2))
		for attempt in 64:
			var x := x0 + rng.randi_range(0, 7) - rng.randi_range(0, 7)
			var y := y0 + rng.randi_range(0, 3) - rng.randi_range(0, 3)
			var z := z0 + rng.randi_range(0, 7) - rng.randi_range(0, 7)
			if x < 0 or x > 15 or z < 0 or z > 15 or y < 1 or y >= _h - 1:
				continue
			# Under a roof: the open sky would be too bright.
			if blocks[index(x, y, z)] == Blocks.AIR and Blocks.is_opaque_table[blocks[index(x, y - 1, z)]] == 1 \
					and y < _surface_y(blocks, x, z):
				blocks[index(x, y, z)] = id


## Springs like the classic game: single water (50 tries) and lava (20 tries)
## sources in cave walls - stone above, below and on three sides, air on
## the fourth. They start flowing when the player comes near.
func _place_springs(blocks: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var stone: int = _id["stone"]
	for kind: Array in [["water_spring", 50], ["lava_spring", 20]]:
		for attempt in kind[1]:
			var x := rng.randi_range(1, 14)
			var z := rng.randi_range(1, 14)
			var y := 0
			if kind[0] == "water_spring":
				y = rng.randi_range(0, rng.randi_range(0, 119) + 7)
			else:
				y = rng.randi_range(0, rng.randi_range(0, rng.randi_range(0, 111) + 7) + 7)
			if y < 1 or y >= _h - 1 or blocks[index(x, y, z)] != stone:
				continue
			if blocks[index(x, y + 1, z)] != stone or blocks[index(x, y - 1, z)] != stone:
				continue
			var walls := 0
			var air := 0
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var side := blocks[index(x + offset.x, y, z + offset.y)]
				if side == stone:
					walls += 1
				elif side == Blocks.AIR:
					air += 1
			if walls == 3 and air == 1:
				blocks[index(x, y, z)] = _id[kind[0]]


## Ice on the sea surface of cold biomes; snow lying on the land and trees.
func _freeze(blocks: PackedInt32Array, biomes: PackedByteArray) -> void:
	var water: int = _id["water"]
	var ice: int = _id["ice"]
	var y := SEA - 1
	for z in 16:
		for x in 16:
			if _biome_cold[biomes[z * 16 + x]] == 1:
				var i := index(x, y, z)
				if blocks[i] == water and blocks[index(x, y + 1, z)] == Blocks.AIR:
					blocks[i] = ice
				# A snow layer on the highest block, if it can hold one.
				var top := _surface_y(blocks, x, z)
				if top > 0 and top < _h - 1:
					var under := blocks[index(x, top, z)]
					if Blocks.is_opaque_table[under] == 1 or Blocks.get_type(under).name.ends_with("_leaves"):
						blocks[index(x, top + 1, z)] = _id["snow_layer"]
