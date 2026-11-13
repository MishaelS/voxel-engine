class_name DebugGenerator
extends WorldGenerator
## "Debug Mode", like the game's debug world: every block of the game in
## every state (each facing, level, half... is its own id, Blocks) standing
## in a grid on a stone floor, two blocks apart so each can be walked
## around, and a row of every creature (VoxelWorld.place_debug_mobs). The
## world doesn't change by itself (no random ticks, no spawning: VoxelWorld),
## so blocks that would need support or flow stay as they are shown.

const FLOOR_Y := 60
const SPACING := 2
## The floor reaches this far around the grid (the creatures stand on it).
const MARGIN := 10


## Every block id but air, in order.
static func shown_blocks() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for id in range(1, Blocks.count()):
		ids.append(id)
	return ids


## Blocks a row of the grid.
static func side() -> int:
	return ceili(sqrt(Blocks.count() - 1))


## Where the block `n` of shown_blocks() stands.
static func cell(n: int) -> Vector3i:
	return Vector3i(1 + (n % side()) * SPACING, FLOOR_Y + 1, 1 + (n / side()) * SPACING)


func generate_blocks(cx: int, cz: int) -> PackedInt32Array:
	var blocks := super(cx, cz)
	var size := side()
	var span := size * SPACING + 1
	if cx * 16 + 15 < -MARGIN or cz * 16 + 15 < -MARGIN or cx * 16 > span + MARGIN or cz * 16 > span + MARGIN:
		return blocks
	var stone := Blocks.id_of("stone")
	var ids := shown_blocks()
	for z in 16:
		for x in 16:
			var wx := cx * 16 + x
			var wz := cz * 16 + z
			if wx < -MARGIN or wz < -MARGIN or wx > span + MARGIN or wz > span + MARGIN:
				continue
			blocks[index(x, FLOOR_Y, z)] = stone
			if wx < 1 or wz < 1 or (wx - 1) % SPACING != 0 or (wz - 1) % SPACING != 0:
				continue
			var n := (wx - 1) / SPACING + (wz - 1) / SPACING * size
			if (wx - 1) / SPACING < size and n < ids.size():
				blocks[index(x, FLOOR_Y + 1, z)] = ids[n]
	return blocks


func biome_name(_x: int, _z: int) -> String:
	return "debug"
