class_name WorldGenerator
extends RefCounted
## Base of world generators. A generator fills one column of the world
## (16 x HEIGHT x 16 blocks) at a time; columns are generated on worker
## threads, so generate_blocks() must only read shared state.

const HEIGHT := 256
const HEIGHT_CHUNKS := HEIGHT / ChunkData.SIZE
const SEA_LEVEL := 128
const COLUMN_VOLUME := ChunkData.SIZE * ChunkData.SIZE * HEIGHT
## Worlds made when the world was 128 high (sea at 64): their blocks are
## LEGACY_SHIFT lower; converted on load (convert_legacy, WorldSave).
const LEGACY_HEIGHT := 128
const LEGACY_SHIFT := 64
const LEGACY_VOLUME := ChunkData.SIZE * ChunkData.SIZE * LEGACY_HEIGHT

var world_seed := 0


func _init(seed_value: int) -> void:
	world_seed = seed_value


## Fills a column: index = x + 16 * (z + 16 * y), the same layout as chunks,
## so chunk k is the range [k * 4096, (k + 1) * 4096). Block ids are 32-bit
## (ChunkData).
func generate_blocks(_cx: int, _cz: int) -> PackedInt32Array:
	var blocks := PackedInt32Array()
	blocks.resize(COLUMN_VOLUME)
	return blocks


## Grass and foliage colors (linear, index x + 16 * z) of a column, or
## empty arrays for the blocks' own tints.
func column_colors(_cx: int, _cz: int) -> Array[PackedColorArray]:
	return [PackedColorArray(), PackedColorArray()]


## A column saved when the world was 128 high, in the 256 high world: its
## blocks 64 up, the classic bedrock floor replaced, the new deep layer
## under it and air above, both from the generator (which makes the same
## terrain there in converted worlds).
func convert_legacy(cx: int, cz: int, old: PackedInt32Array) -> PackedInt32Array:
	var blocks := generate_blocks(cx, cz)
	var bedrock := Blocks.id_of("bedrock")
	for y in LEGACY_HEIGHT:
		for i in 256:
			var id := old[i + 256 * y]
			if y <= 4 and id == bedrock:
				continue # the old floor: the deep layer goes on below
			blocks[i + 256 * (y + LEGACY_SHIFT)] = id
	return blocks


## Name of the biome at a block column (for the debug screen).
func biome_name(_x: int, _z: int) -> String:
	return "none"


## Highest block that affects sky light (light opacity > 0) per block
## column, index x + 16 * z; -1 if none. Everything above it gets full sky.
static func heightmap(blocks: PackedInt32Array) -> PackedInt32Array:
	var opacity := Blocks.light_opacity_table
	var heights := PackedInt32Array()
	heights.resize(256)
	for column in 256:
		var top := -1
		var i := column + 256 * (HEIGHT - 1)
		for y in range(HEIGHT - 1, -1, -1):
			if opacity[blocks[i]] > 0:
				top = y
				break
			i -= 256
		heights[column] = top
	return heights


## The column split into its chunks, bottom to top.
func generate_column(cx: int, cz: int) -> Array[ChunkData]:
	return split_column(generate_blocks(cx, cz))


## Chunks of a generated column, bottom to top.
static func split_column(blocks: PackedInt32Array) -> Array[ChunkData]:
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
