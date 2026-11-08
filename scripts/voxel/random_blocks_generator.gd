class_name RandomBlocksGenerator
extends RefCounted
## Debug generator: a floor plus randomly scattered blocks of every type.
## Shows how textures meet at seams, how transparent blocks cull each other,
## and how AO and shadows behave in dense, irregular geometry.

const FLOOR_BLOCK := "stone"

var density := 0.3
var _seed := 0


func _init(world_seed: int, block_density: float = 0.3) -> void:
	_seed = world_seed
	density = block_density


func fill(data: ChunkData, chunk_coord: Vector3i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, chunk_coord])
	var floor_id := Blocks.id_of(FLOOR_BLOCK)
	var last_id := Blocks.count() - 1

	for y in ChunkData.SIZE:
		for z in ChunkData.SIZE:
			for x in ChunkData.SIZE:
				var id := Blocks.AIR
				if y == 0:
					id = floor_id
				elif rng.randf() < density:
					id = rng.randi_range(1, last_id)
				data.set_block(x, y, z, id)
