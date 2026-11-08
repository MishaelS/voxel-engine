class_name ChunkData
extends RefCounted
## Block storage of one cubic chunk (SIZE^3 blocks), one byte per block.
## A flat array is cache-friendly and cheap to copy to worker threads.

const SIZE := 16
const VOLUME := SIZE * SIZE * SIZE

var blocks := PackedByteArray()


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
	blocks[index(x, y, z)] = id


## Returns AIR outside the chunk.
## TODO: look up neighbor chunks once there is more than one chunk.
func get_block_or_air(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return Blocks.AIR
	return blocks[index(x, y, z)]


func count_solid() -> int:
	var count := 0
	for id in blocks:
		if id != Blocks.AIR:
			count += 1
	return count
