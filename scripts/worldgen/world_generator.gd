class_name WorldGenerator
extends RefCounted
## Base of world generators. A generator fills one column of the world
## (16 x HEIGHT x 16 blocks) at a time; columns are generated on worker
## threads, so generate_blocks() must only read shared state.

const HEIGHT := 128
const HEIGHT_CHUNKS := HEIGHT / ChunkData.SIZE
const SEA_LEVEL := 64
const COLUMN_VOLUME := ChunkData.SIZE * ChunkData.SIZE * HEIGHT

var world_seed := 0


func _init(seed_value: int) -> void:
	world_seed = seed_value


## Fills a column: index = x + 16 * (z + 16 * y), the same layout as chunks,
## so chunk k is the byte range [k * 4096, (k + 1) * 4096).
func generate_blocks(_cx: int, _cz: int) -> PackedByteArray:
	var blocks := PackedByteArray()
	blocks.resize(COLUMN_VOLUME)
	return blocks


## Name of the biome at a block column (for the debug screen).
func biome_name(_x: int, _z: int) -> String:
	return "none"


## Highest block that affects sky light (light opacity > 0) per block
## column, index x + 16 * z; -1 if none. Everything above it gets full sky.
static func heightmap(blocks: PackedByteArray) -> PackedInt32Array:
	var opacity := Blocks.light_opacity_table
	var heights := PackedInt32Array()
	heights.resize(256)
	for z in 16:
		for x in 16:
			var top := -1
			for y in range(HEIGHT - 1, -1, -1):
				if opacity[blocks[index(x, y, z)]] > 0:
					top = y
					break
			heights[x + 16 * z] = top
	return heights


## The column split into its chunks, bottom to top.
func generate_column(cx: int, cz: int) -> Array[ChunkData]:
	var blocks := generate_blocks(cx, cz)
	var chunks: Array[ChunkData] = []
	for k in HEIGHT_CHUNKS:
		var chunk := ChunkData.new()
		chunk.blocks = blocks.slice(k * ChunkData.VOLUME, (k + 1) * ChunkData.VOLUME)
		chunk.count_tickable()
		chunks.append(chunk)
	return chunks


static func index(x: int, y: int, z: int) -> int:
	return x + 16 * (z + 16 * y)


## Deterministic random source for a column and a purpose.
func column_rng(cx: int, cz: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, cx, cz, salt])
	return rng
