class_name FloatingIslandsGenerator
extends BetaGenerator
## "Floating Islands": islands of land hanging in the sky over an empty void
## (no sea, no bedrock), with Beta's biomes, ores, trees, plants, lakes and
## springs (waterfalls into the void). An island's shape is a 3D noise on a
## coarse grid (like Beta's terrain), cut by a 2D noise into separate
## islands and squeezed around a wavy middle height: flat tops, deep
## rounded undersides. There is always an island at the world's center
## (the spawn).

const GRID := 4
const CELLS := 16 / GRID
## The islands' middle height, and how far it waves up and down.
const MIDDLE := 100.0
const MIDDLE_WAVE := 36.0
## How quickly the land thins out above / below the middle.
const TOP_THICKNESS := 12.0
const BOTTOM_THICKNESS := 34.0
## The island at the spawn: this many blocks across.
const SPAWN_RADIUS := 40.0
## Ores at any height (the islands are where the stone is).
const ISLAND_ORES := [
	["dirt", 10, 32, 200],
	["gravel", 5, 32, 200],
	["coal_ore", 20, 16, 200],
	["iron_ore", 20, 8, 200],
	["gold_ore", 4, 8, 200],
	["redstone_ore", 8, 7, 200],
	["diamond_ore", 3, 7, 200],
	["lapis_ore", 2, 6, 200],
]

var _shape_noise := FastNoiseLite.new()
var _island_noise := FastNoiseLite.new()
var _middle_noise := FastNoiseLite.new()


func _init(seed_value: int) -> void:
	super(seed_value)
	set_layout(WorldSave.layout_of(WorldSave.FLOATING))
	_setup(_shape_noise, 50, 0.018, 3)
	_setup(_island_noise, 51, 0.007, 3)
	_setup(_middle_noise, 52, 0.004, 2)


## How solid the world is at a point (> 0: stone).
func density(wx: float, y: float, wz: float) -> float:
	var middle := MIDDLE + _middle_noise.get_noise_2d(wx, wz) * MIDDLE_WAVE * 2.0
	var dy := y - middle
	var squeeze := dy / TOP_THICKNESS if dy > 0.0 else dy / BOTTOM_THICKNESS
	var value := _shape_noise.get_noise_3d(wx, y * 1.5, wz) * 1.2 + _island_noise.get_noise_2d(wx, wz) * 2.4 \
		- 0.55 - squeeze * squeeze
	var spawn := 1.0 - Vector2(wx, wz).length() / SPAWN_RADIUS
	if spawn > 0.0:
		value += spawn * 1.2
	return value


func generate_blocks(cx: int, cz: int) -> PackedInt32Array:
	var blocks := PackedInt32Array()
	blocks.resize(COLUMN_VOLUME)
	var top := _shape(blocks, cx, cz)
	if top < 0:
		return blocks # only sky here
	var climate_values := climate(cx, cz)
	var biomes := PackedByteArray()
	biomes.resize(256)
	for i in 256:
		biomes[i] = biome_index(climate_values[i], climate_values[256 + i])
	_cover(blocks, biomes)
	var rng := column_rng(cx, cz, 100)
	_place_water_lake(blocks, column_rng(cx, cz, 250))
	_place_ores(blocks, rng, top, ISLAND_ORES)
	_place_trees(blocks, cx, cz, biomes, rng)
	_place_plants(blocks, biomes, column_rng(cx, cz, 300))
	var nature := column_rng(cx, cz, 500)
	_place_sugar_cane(blocks, nature)
	_place_mushrooms(blocks, nature)
	_place_springs(blocks, nature)
	_freeze(blocks, biomes)
	return blocks


## The islands' stone from the density on the grid, interpolated in
## between; returns the highest stone (-1: none).
func _shape(blocks: PackedInt32Array, cx: int, cz: int) -> int:
	var stone: int = _id["stone"]
	var cells_y := _h / GRID
	var stride_y := cells_y + 1
	var stride_z := (CELLS + 1) * stride_y
	var values := PackedFloat32Array()
	values.resize((CELLS + 1) * stride_z)
	var any := false
	for gx in CELLS + 1:
		for gz in CELLS + 1:
			for gy in stride_y:
				var value := density(cx * 16 + gx * GRID, gy * GRID, cz * 16 + gz * GRID)
				if gy == 0 or gy >= cells_y - 1:
					value = -1.0 # (nothing at the world's floor and ceiling)
				values[gx * stride_z + gz * stride_y + gy] = value
				any = any or value > 0.0
	if not any:
		return -1
	var top := -1
	for gx in CELLS:
		for gz in CELLS:
			for gy in cells_y:
				var base := gx * stride_z + gz * stride_y + gy
				var d000 := values[base]
				var d001 := values[base + stride_y]
				var d100 := values[base + stride_z]
				var d101 := values[base + stride_z + stride_y]
				var d010 := values[base + 1]
				var d011 := values[base + stride_y + 1]
				var d110 := values[base + stride_z + 1]
				var d111 := values[base + stride_z + stride_y + 1]
				if maxf(maxf(maxf(d000, d001), maxf(d100, d101)), maxf(maxf(d010, d011), maxf(d110, d111))) <= 0.0:
					continue # all air
				for sy in GRID:
					var ty := sy / float(GRID)
					var y := gy * GRID + sy
					var a00 := d000 + (d010 - d000) * ty
					var a01 := d001 + (d011 - d001) * ty
					var a10 := d100 + (d110 - d100) * ty
					var a11 := d101 + (d111 - d101) * ty
					for sx in GRID:
						var tx := sx / float(GRID)
						var b0 := a00 + (a10 - a00) * tx
						var b1 := a01 + (a11 - a01) * tx
						for sz in GRID:
							if b0 + (b1 - b0) * (sz / float(GRID)) > 0.0:
								blocks[index(gx * GRID + sx, y, gz * GRID + sz)] = stone
								top = maxi(top, y)
	return top


## Grass (the biome's) on every top with air above, dirt under it; deserts
## sand on sandstone (sand would fall off the islands' undersides).
func _cover(blocks: PackedInt32Array, biomes: PackedByteArray) -> void:
	var stone: int = _id["stone"]
	var dirt: int = _id["dirt"]
	for z in 16:
		for x in 16:
			var biome := biomes[z * 16 + x]
			var top: int = _biome_top[biome]
			var filler: int = _biome_filler[biome]
			if filler == _id["sand"]:
				filler = _id["sandstone"]
			if filler != _id["sandstone"]:
				filler = dirt
			var depth := -1
			for y in range(_h - 2, 0, -1):
				var i := index(x, y, z)
				if blocks[i] != stone:
					depth = -1
					continue
				if depth == -1:
					blocks[i] = top if blocks[i - 256] != Blocks.AIR or top != _id["sand"] else filler
					depth = 3
				elif depth > 0:
					depth -= 1
					blocks[i] = filler
