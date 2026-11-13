class_name IslandGenerator
extends BetaGenerator
## "Island": Beta's land (biomes, caves, ores, trees) as one big island
## around the world's center in an endless sea. Past ISLAND_RADIUS (its
## shore going in and out by a noise) the ground slopes down over SHORE
## blocks to a sea floor about OCEAN_DEPTH under the water. Seas inside the
## island are filled up into low land, so the spawn is always on ground.
## The land is Beta's column (native or not) reshaped afterwards: the
## columns the island leaves as they were are block for block Beta's.

const ISLAND_RADIUS := 260.0
const WOBBLE := 110.0
const SHORE := 100.0
const OCEAN_DEPTH := 14

var _shore_noise := FastNoiseLite.new()
## Blocks standing on the ground rather than being it (logs, leaves,
## plants, ice, snow): looking for the ground skips them.
var _not_ground := PackedByteArray()


func _init(seed_value: int) -> void:
	super(seed_value)
	_setup(_shore_noise, 40, 0.004, 3)
	_not_ground.resize(Blocks.count())
	for id in Blocks.count():
		var block_name := Blocks.get_type(id).name
		_not_ground[id] = 1 if Blocks.collides_table[id] == 0 or Blocks.liquid_table[id] == 1 \
			or block_name.contains("_log") or block_name.contains("leaves") or block_name.contains("ice") \
			or block_name.contains("pumpkin") or block_name.contains("cactus") else 0


func generate_blocks(cx: int, cz: int) -> PackedInt32Array:
	var blocks := super(cx, cz)
	var climate_values := climate(cx, cz)
	for z in 16:
		for x in 16:
			var wx := float(cx * 16 + x)
			var wz := float(cz * 16 + z)
			var edge := ISLAND_RADIUS + _shore_noise.get_noise_2d(wx, wz) * WOBBLE
			var t := smoothstep(edge - SHORE * 0.5, edge + SHORE * 0.5, Vector2(wx, wz).length())
			var ground := _ground(blocks, x, z)
			var land := ground if ground >= SEA else SEA + 1 # (seas inside: low grassland)
			var floor_y := SEA - OCEAN_DEPTH + roundi(_shore_noise.get_noise_2d(wz * 3.0, wx * 3.0) * 6.0)
			var target := roundi(lerpf(land, floor_y, t))
			if target == ground:
				continue
			var biome := biome_index(climate_values[z * 16 + x], climate_values[256 + z * 16 + x])
			_reshape(blocks, x, z, ground, target, biome)
	return blocks


## The highest block of the ground at (x, z), or 0.
func _ground(blocks: PackedInt32Array, x: int, z: int) -> int:
	for y in range(_h - 1, 0, -1):
		var id := blocks[index(x, y, z)]
		if id != Blocks.AIR and _not_ground[id] == 0:
			return y
	return 0


## The column with its ground at `target` instead of `ground`: cut down (the
## sea below its level) or filled up with dirt, then a new top: sand on the
## beach and under the water, the biome's grass above.
func _reshape(blocks: PackedInt32Array, x: int, z: int, ground: int, target: int, biome: int) -> void:
	for y in range(target + 1, _h):
		blocks[index(x, y, z)] = _water if y < SEA else Blocks.AIR
	var filler: int = _biome_filler[biome]
	for y in range(ground + 1, target + 1):
		blocks[index(x, y, z)] = _id["stone"] if y < target - 3 else filler
	var top: int = _biome_top[biome]
	if target <= SEA:
		top = _id["sand"]
		filler = _id["sand"]
	elif filler == _id["sand"]:
		filler = _id["sandstone"] # (desert sand doesn't hang over caves)
	blocks[index(x, target, z)] = top
	for y in range(maxi(target - 3, 1), target):
		var i := index(x, y, z)
		if blocks[i] != Blocks.AIR and Blocks.liquid_table[blocks[i]] == 0:
			blocks[i] = filler if filler != _id["sand"] or blocks[i - 256] != Blocks.AIR else _id["sandstone"]
	if target > SEA and _biome_cold[biome] == 1:
		blocks[index(x, target + 1, z)] = _id["snow_layer"]
