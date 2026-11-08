class_name TerrainGenerator
extends RefCounted
## Simple heightmap terrain: grass on top, a few layers of dirt, stone below.

const MIN_HEIGHT := 3
const MAX_HEIGHT := 13
const DIRT_DEPTH := 3

var _noise := FastNoiseLite.new()


func _init(world_seed: int) -> void:
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.06


func fill(data: ChunkData, chunk_coord: Vector3i) -> void:
	var origin := chunk_coord * ChunkData.SIZE
	for z in ChunkData.SIZE:
		for x in ChunkData.SIZE:
			var n := _noise.get_noise_2d(origin.x + x, origin.z + z)
			var height := int(remap(n, -1.0, 1.0, MIN_HEIGHT, MAX_HEIGHT))
			for y in ChunkData.SIZE:
				var world_y := origin.y + y
				var id := Blocks.AIR
				if world_y == height - 1:
					id = Blocks.GRASS
				elif world_y >= height - 1 - DIRT_DEPTH and world_y < height - 1:
					id = Blocks.DIRT
				elif world_y < height - 1 - DIRT_DEPTH:
					id = Blocks.STONE
				data.set_block(x, y, z, id)
