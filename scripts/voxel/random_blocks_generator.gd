class_name RandomBlocksGenerator
extends WorldGenerator
## Debug generator: in the column at the origin, a stone floor plus every
## block type scattered randomly over the first 16 blocks of height; the
## rest of the world is empty. Shows texture seams, transparency, AO and
## shadows in dense, irregular geometry.

var density := 0.3


func _init(seed_value: int, block_density: float = 0.3) -> void:
	super(seed_value)
	density = block_density


func generate_blocks(cx: int, cz: int) -> PackedByteArray:
	var blocks := super(cx, cz)
	if cx != 0 or cz != 0:
		return blocks
	var rng := column_rng(cx, cz, 0)
	var floor_id := Blocks.id_of("stone")
	var last_id := Blocks.count() - 1
	for y in ChunkData.SIZE:
		for z in ChunkData.SIZE:
			for x in ChunkData.SIZE:
				if y == 0:
					blocks[index(x, y, z)] = floor_id
				elif rng.randf() < density:
					blocks[index(x, y, z)] = rng.randi_range(1, last_id)
	return blocks


func biome_name(_x: int, _z: int) -> String:
	return "debug"
