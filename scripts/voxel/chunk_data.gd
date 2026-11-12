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
## Sky light per block (0..15), same layout as `blocks`. Filled by
## SkyLight when the column is lit, then kept up to date by VoxelWorld.
var light := PackedByteArray()
## Light from glowing blocks (torches, lava; 0..15), same layout. Filled by
## BlockLight with the sky light, kept up to date by VoxelWorld.
var block_light := PackedByteArray()


func _init() -> void:
	blocks.resize(VOLUME) # zero-filled = AIR
	light.resize(VOLUME)
	block_light.resize(VOLUME)


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
	blocks[i] = id


## Recounts tickable_count and air_count after filling `blocks` directly
## (generators).
func count_tickable() -> void:
	air_count = blocks.count(Blocks.AIR)
	tickable_count = 0
	if air_count == VOLUME:
		return
	var ticks := Blocks.ticks_randomly
	for id in blocks:
		tickable_count += ticks[id]


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
