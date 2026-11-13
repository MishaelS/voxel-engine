class_name WorldGenerator
extends RefCounted
## Base of world generators. A generator fills one column of the world
## (16 x HEIGHT x 16 blocks) at a time; columns are generated on worker
## threads, so generate_blocks() must only read shared state.

## The columns' storage: 256 high, whatever the world's own height
## (WorldSave.layout: classic worlds 128 like Beta 1.7.3, the rest above air).
const HEIGHT := 256
const HEIGHT_CHUNKS := HEIGHT / ChunkData.SIZE
## The sea of classic and tall worlds (the old 256 high worlds: 128).
const SEA_LEVEL := 64
const COLUMN_VOLUME := ChunkData.SIZE * ChunkData.SIZE * HEIGHT
## Columns saved 128 high (classic worlds from before, and old worlds
## from before they became 256 high, LEGACY_SHIFT lower): convert_legacy.
const LEGACY_HEIGHT := 128
const LEGACY_SHIFT := 64
const LEGACY_VOLUME := ChunkData.SIZE * ChunkData.SIZE * LEGACY_HEIGHT

var world_seed := 0
## Where a column saved 128 high goes (WorldSave.layout "shift"): 0 in
## classic worlds, LEGACY_SHIFT up onto the deep layer in old ones.
var legacy_shift := LEGACY_SHIFT


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
	if legacy_shift == 0:
		# A classic world's column: as it was, air above.
		var padded := old.duplicate()
		padded.resize(COLUMN_VOLUME)
		return padded
	var blocks := generate_blocks(cx, cz)
	var bedrock := Blocks.id_of("bedrock")
	var stone := Blocks.id_of("stone")
	for y in LEGACY_HEIGHT:
		for i in 256:
			var id := old[i + 256 * y]
			if y <= 4 and id == bedrock:
				id = stone # the old floor turns to stone: no holes under old lava or water
			blocks[i + 256 * (y + legacy_shift)] = id
	return blocks


## Name of the biome at a block column (for the debug screen).
func biome_name(_x: int, _z: int) -> String:
	return "none"


## Highest block that affects sky light (light opacity > 0) per block
## column, index x + 16 * z; -1 if none. Everything above it gets full sky.
static func heightmap(blocks: PackedInt32Array) -> PackedInt32Array:
	if _native_light:
		return ClassDB.class_call_static("NativeLight", "heightmap", blocks, Blocks.light_opacity_table)
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
	var counts := PackedInt32Array()
	if _native_light:
		counts = ClassDB.class_call_static("NativeLight", "chunk_counts", blocks, Blocks.ticks_randomly,
			Blocks.light_emission_table, Blocks.fast_leaves_table())
	for k in HEIGHT_CHUNKS:
		var chunk := ChunkData.new()
		if counts.is_empty():
			chunk.blocks = blocks.slice(k * ChunkData.VOLUME, (k + 1) * ChunkData.VOLUME)
			chunk.count_tickable()
		else:
			chunk.air_count = counts[k * 4]
			chunk.tickable_count = counts[k * 4 + 1]
			chunk.glow_count = counts[k * 4 + 2]
			chunk.leaf_count = counts[k * 4 + 3]
			if chunk.air_count < ChunkData.VOLUME: # (an empty one keeps the shared air)
				chunk.blocks = blocks.slice(k * ChunkData.VOLUME, (k + 1) * ChunkData.VOLUME)
		chunk.share_uniform()
		chunks.append(chunk)
	return chunks


static var _native_light := ClassDB.class_exists("NativeLight")


static func index(x: int, y: int, z: int) -> int:
	return x + 16 * (z + 16 * y)


## Deterministic random source for a column and a purpose.
func column_rng(cx: int, cz: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, cx, cz, salt])
	return rng
