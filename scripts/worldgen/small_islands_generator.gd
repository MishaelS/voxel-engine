class_name SmallIslandsGenerator
extends BetaGenerator
## "Island": a small island in a deep endless sea - a sandy beach round a
## low grassy hill with a forest on it - and, by the seed, up to
## MAX_ISLETS little islets with a couple of trees some way off. One biome
## (forest) everywhere, no lakes, snow or deserts. Under the island Beta's
## caves, ores and dungeons, so one can live on it.
##
## Its own columns (not Beta's reshaped like the old big island's,
## IslandGenerator, which worlds made before keep): the ground's height
## comes from the islands' outlines alone.

## The main island's radius (blocks), by the seed.
const MAIN_RADIUS := Vector2(44.0, 60.0)
const MAX_ISLETS := 3
const ISLET_RADIUS := Vector2(13.0, 26.0)
## How far from the middle the islets lie.
const ISLET_DISTANCE := Vector2(130.0, 340.0)
## The sea floor far from land, under the sea level.
const OCEAN_DEPTH := 36.0
## The outline's parts in radii: the hill ends, the beach meets the water
## (1.0), the shallows end, the slope reaches the sea floor.
const HILL := 0.75
const SHALLOWS := 1.3
const SLOPE := 2.3

## The islands: Vector3(x, z, radius); the first is the main one.
var _islands: Array[Vector3] = []
## Each island's own shape: Vector2(how much narrower it is one way than
## the other (0.55..1), which way it is turned).
var _shapes: Array[Vector2] = []
var _outline_noise := FastNoiseLite.new()
## Small bays and capes on top of the outline's big ones.
var _detail_outline_noise := FastNoiseLite.new()
var _floor_noise := FastNoiseLite.new()
## The land's own ups and downs: knolls and hollows on the hill.
var _hill_noise := FastNoiseLite.new()


func _init(seed_value: int) -> void:
	super(seed_value)
	_setup(_outline_noise, 41, 0.02, 3)
	_setup(_floor_noise, 42, 0.01, 3)
	_setup(_detail_outline_noise, 44, 0.06, 2)
	_setup(_hill_noise, 45, 0.045, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, 43])
	_islands.append(Vector3(8.0, 8.0, rng.randf_range(MAIN_RADIUS.x, MAIN_RADIUS.y)))
	_shapes.append(Vector2(rng.randf_range(0.55, 0.9), rng.randf() * PI))
	for i in rng.randi_range(0, MAX_ISLETS):
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(ISLET_DISTANCE.x, ISLET_DISTANCE.y)
		_islands.append(Vector3(8.0 + cos(angle) * distance, 8.0 + sin(angle) * distance,
			rng.randf_range(ISLET_RADIUS.x, ISLET_RADIUS.y)))
		_shapes.append(Vector2(rng.randf_range(0.55, 1.0), rng.randf() * PI))


## One biome everywhere: forest (its grass color, trees and plants).
func temperature(_x: float, _z: float) -> float:
	return 0.8


func humidity(_x: float, _z: float) -> float:
	return 0.6


## The ground's height at a block column (its top block's y) and, in y, how
## wooded it is there (1 the main island, 0.2 an islet, 0 the sea).
func ground_at(wx: float, wz: float) -> Vector2:
	var sea_floor := SEA - OCEAN_DEPTH + _floor_noise.get_noise_2d(wx, wz) * 6.0
	var height := sea_floor
	var wooded := 0.0
	# Uneven on purpose: the shore goes in and out (big bays and capes, small
	# ones on top), the beach is wide here and narrow there, the land rises
	# in knolls with hollows between them.
	var wobble := maxf(1.0 + _outline_noise.get_noise_2d(wx, wz) * 0.55 + _detail_outline_noise.get_noise_2d(wx, wz) * 0.16, 0.35)
	var hill_edge := clampf(HILL + _detail_outline_noise.get_noise_2d(wz, wx) * 0.2, 0.5, 0.92)
	var bumps := _hill_noise.get_noise_2d(wx, wz)
	for i in _islands.size():
		var island := _islands[i]
		var shape := _shapes[i]
		# (stretched one way and turned: not a circle)
		var offset := Vector2(wx - island.x, wz - island.y).rotated(shape.y)
		offset.y /= shape.x
		var d := offset.length() / (island.z * wobble)
		if d >= SLOPE:
			continue
		var y: float
		if d < hill_edge:
			# The hill: higher the bigger the island, its top far from even.
			var peak := clampf(island.z / 6.0, 2.0, 10.0)
			var inward := 1.0 - smoothstep(0.0, hill_edge, d)
			y = SEA + 2.0 + peak * inward * (0.55 + bumps * 0.9) + bumps * 2.0 * minf(inward * 4.0, 1.0)
			y = maxf(y, SEA + 2.0)
		elif d < 1.0:
			y = lerpf(SEA + 2.0, SEA, (d - hill_edge) / (1.0 - hill_edge)) # the beach
		elif d < SHALLOWS:
			y = lerpf(SEA, SEA - 5.0, (d - 1.0) / (SHALLOWS - 1.0))
		else:
			y = lerpf(SEA - 5.0, sea_floor, smoothstep(SHALLOWS, SLOPE, d))
		if y > height:
			height = y
			wooded = 0.0 if d >= hill_edge else (1.0 if i == 0 else 0.2)
	return Vector2(roundf(height), wooded)


func generate_blocks(cx: int, cz: int) -> PackedInt32Array:
	var stone: int = _id["stone"]
	var sand: int = _id["sand"]
	var sandstone: int = _id["sandstone"]
	var gravel: int = _id["gravel"]
	var dirt: int = _id["dirt"]
	var grass: int = _biome_top[3] # forest
	var heights := PackedInt32Array()
	heights.resize(256)
	var lowest := _h
	var highest := 0
	var wooded := 0.0
	for z in 16:
		for x in 16:
			var ground := ground_at(cx * 16 + x, cz * 16 + z)
			var y := clampi(int(ground.x), 6, _h - 24)
			heights[x + 16 * z] = y
			lowest = mini(lowest, y)
			highest = maxi(highest, y)
			wooded = maxf(wooded, ground.y)
	# Solid stone under the lowest ground (whole layers at once), the rest
	# column by column: stone, 3 of the top's filler, the top; the sea above.
	var blocks := PackedInt32Array()
	var solid := maxi(lowest - 4, 1)
	blocks.resize(256 * solid)
	blocks.fill(stone)
	blocks.resize(256 * (highest + 1))
	for z in 16:
		for x in 16:
			var y := heights[x + 16 * z]
			var beach := y <= SEA + 1
			var deep := y < SEA - 12 and _gravel_noise.get_noise_2d(cx * 16 + x, cz * 16 + z) > 0.15
			var top := grass if not beach else (gravel if deep else sand)
			var filler := dirt if not beach else (gravel if deep else sand)
			for by in range(solid, y - 3):
				blocks[index(x, by, z)] = stone
			for by in range(maxi(y - 3, solid), y):
				blocks[index(x, by, z)] = filler
			if filler == sand and y - 4 >= solid:
				blocks[index(x, y - 4, z)] = sandstone # (sand doesn't hang over caves)
			blocks[index(x, y, z)] = top
			for by in range(y + 1, mini(highest + 1, SEA)):
				blocks[index(x, by, z)] = _water
	# The sea over the highest ground: whole layers of water.
	if highest + 1 < SEA:
		var layer := PackedInt32Array()
		layer.resize(256)
		layer.fill(_water)
		for by in range(highest + 1, SEA):
			blocks.append_array(layer)
	blocks.resize(COLUMN_VOLUME)
	_place_floor(blocks, cx, cz)
	# Underground like Beta's: caves (never opened into water), dungeons, ores.
	# Under the open sea only the ores: nobody gets down there, and the
	# sea is most of the world's columns.
	if highest >= SEA - 8:
		_carve_caves(blocks, cx, cz, 2, 119, _h - 8, -1)
		DungeonBehavior.place(blocks, column_rng(cx, cz, 600), _h, _dungeon_ids)
	var rng := column_rng(cx, cz, 100)
	_place_ores(blocks, rng, highest, ORES)
	if highest > SEA:
		var biomes := PackedByteArray()
		biomes.resize(256)
		biomes.fill(3) # forest
		_place_island_trees(blocks, wooded, rng)
		_place_plants(blocks, biomes, column_rng(cx, cz, 300))
	if highest >= SEA - 8:
		_place_clay(blocks, column_rng(cx, cz, 400))
		var nature := column_rng(cx, cz, 500)
		_place_sugar_cane(blocks, nature)
		_place_mushrooms(blocks, nature)
	return blocks


## Trees on the grass: a forest on the main island (`wooded` 1), a tree or
## two on an islet.
func _place_island_trees(blocks: PackedInt32Array, wooded: float, rng: RandomNumberGenerator) -> void:
	if wooded <= 0.0:
		return
	var count := rng.randi_range(3, 6) if wooded >= 1.0 else rng.randi_range(0, 2)
	var canvas := TreeShapes.ColumnCanvas.new(blocks, _h)
	for t in count:
		var kind := _tree_kind("forest", rng)
		var margin: int = TREE_MARGINS[kind]
		var x := clampi(rng.randi_range(2, 13), margin, 15 - margin)
		var z := clampi(rng.randi_range(2, 13), margin, 15 - margin)
		var y := _surface_y(blocks, x, z)
		if y <= SEA + 1 or not TreeShapes.is_ground(blocks[index(x, y, z)]) or blocks[index(x, y, z)] == _id["sand"]:
			continue # (not on the beach)
		match kind:
			"oak":
				TreeShapes.oak(canvas, rng, x, y + 1, z, _id["oak_log"], _id["oak_leaves"], 4)
			"birch":
				TreeShapes.oak(canvas, rng, x, y + 1, z, _id["birch_log"], _id["birch_leaves"], 5)
			"big_oak":
				TreeShapes.big_oak(canvas, rng, x, y + 1, z)
