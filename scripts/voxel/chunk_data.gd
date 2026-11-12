class_name ChunkData
extends RefCounted
## Block storage of one cubic chunk (SIZE^3 blocks) and its light.
## Block ids are 32-bit (PackedInt32Array): every block state is its own id
## (facings, levels, halves...), so there can be far more than 256. Flat
## arrays are cache-friendly and cheap to copy to worker threads.

const SIZE := 16
const VOLUME := SIZE * SIZE * SIZE

var blocks := PackedInt32Array()
## Number of blocks with a random tick handler (grass...). Chunks with none
## are skipped by random ticks.
var tickable_count := 0
## Number of air blocks: a chunk of only air has nothing to draw and is
## skipped by meshing (most of the sky in a 256 high world).
var air_count := VOLUME
## Number of glowing blocks (torches, lava...): block light only looks for
## its sources in chunks that have some.
var glow_count := 0
## Sky light per block (0..15), same layout as `blocks`. Filled by
## SkyLight when the column is lit, then kept up to date by VoxelWorld.
var light := PackedByteArray()
## Light from glowing blocks (torches, lava; 0..15), same layout. Filled by
## BlockLight with the sky light, kept up to date by VoxelWorld.
var block_light := PackedByteArray()


## Arrays every chunk of only air / of full sky light / of no light shares
## (packed arrays copy on write: a chunk that changes gets its own). Most
## of a 256 high world is sky: this keeps its memory to almost nothing.
static var _air_blocks := _filled_ints(0)
static var _full_light := _filled_bytes(15)
static var _no_light := _filled_bytes(0)


static func _filled_ints(value: int) -> PackedInt32Array:
	var array := PackedInt32Array()
	array.resize(VOLUME)
	array.fill(value)
	return array


static func _filled_bytes(value: int) -> PackedByteArray:
	var array := PackedByteArray()
	array.resize(VOLUME)
	array.fill(value)
	return array


func _init() -> void:
	blocks = _air_blocks # (all AIR)
	light = _no_light
	block_light = _no_light


## Shares the arrays that are all one value (after generating or lighting).
func share_uniform() -> void:
	if air_count == VOLUME:
		blocks = _air_blocks
	if light.count(15) == VOLUME:
		light = _full_light
	elif light.count(0) == VOLUME:
		light = _no_light
	if block_light.count(0) == VOLUME:
		block_light = _no_light


## Layout: x changes fastest, then z, then y (horizontal layers).
static func index(x: int, y: int, z: int) -> int:
	return x + SIZE * (z + SIZE * y)


static func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < SIZE and y < SIZE and z < SIZE


func get_block(x: int, y: int, z: int) -> int:
	return blocks[index(x, y, z)]


func set_block(x: int, y: int, z: int, id: int) -> void:
	var i := index(x, y, z)
	var old := blocks[i]
	tickable_count += Blocks.ticks_randomly[id] - Blocks.ticks_randomly[old]
	air_count += int(id == Blocks.AIR) - int(old == Blocks.AIR)
	glow_count += int(Blocks.light_emission_table[id] > 0) - int(Blocks.light_emission_table[old] > 0)
	blocks[i] = id


## Recounts tickable_count and air_count after filling `blocks` directly
## (generators).
func count_tickable() -> void:
	air_count = blocks.count(Blocks.AIR)
	tickable_count = 0
	glow_count = 0
	if air_count == VOLUME:
		return
	var ticks := Blocks.ticks_randomly
	var emission := Blocks.light_emission_table
	for id in blocks:
		tickable_count += ticks[id]
		if emission[id] > 0:
			glow_count += 1


## True if every block is air.
func is_empty() -> bool:
	return air_count == VOLUME


## Number of non-air blocks.
func count_solid() -> int:
	return VOLUME - blocks.count(Blocks.AIR)


## Independent copy (e.g. a snapshot for meshing on a worker thread while
## the original keeps changing on the main thread).
func copy() -> ChunkData:
	var result := ChunkData.new()
	result.blocks = blocks.duplicate()
	return result
