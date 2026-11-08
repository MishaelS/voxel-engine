class_name ChunkData
extends RefCounted
## Block storage of one cubic chunk (SIZE^3 blocks), one byte per block.
## A flat array is cache-friendly and cheap to copy to worker threads.

const SIZE := 16
const VOLUME := SIZE * SIZE * SIZE

var blocks := PackedByteArray()
## Number of blocks with a random tick handler (grass...). Chunks with none
## are skipped by random ticks.
var tickable_count := 0


func _init() -> void:
	blocks.resize(VOLUME) # zero-filled = AIR


## Layout: x changes fastest, then z, then y (horizontal layers).
static func index(x: int, y: int, z: int) -> int:
	return x + SIZE * (z + SIZE * y)


static func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < SIZE and y < SIZE and z < SIZE


func get_block(x: int, y: int, z: int) -> int:
	return blocks[index(x, y, z)]


func set_block(x: int, y: int, z: int, id: int) -> void:
	var i := index(x, y, z)
	tickable_count += Blocks.ticks_randomly[id] - Blocks.ticks_randomly[blocks[i]]
	blocks[i] = id


## Recounts tickable_count after filling `blocks` directly (generators).
func count_tickable() -> void:
	var ticks := Blocks.ticks_randomly
	tickable_count = 0
	for id in blocks:
		tickable_count += ticks[id]


## True if every block is air.
func is_empty() -> bool:
	return blocks.count(Blocks.AIR) == VOLUME


## Number of non-air blocks.
func count_solid() -> int:
	return VOLUME - blocks.count(Blocks.AIR)


## Independent copy (e.g. a snapshot for meshing on a worker thread while
## the original keeps changing on the main thread).
func copy() -> ChunkData:
	var result := ChunkData.new()
	result.blocks = blocks.duplicate()
	return result
