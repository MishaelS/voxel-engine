class_name BlockType
extends RefCounted
## Description of one block type: textures per face and render rules.
## Built with the static constructors and chained setters, e.g.
##   BlockType.column("oak_log", 21, 20)
##   BlockType.cube("glass", 49).set_layer(Blocks.Layer.CUTOUT).set_cull_self()

## Face order everywhere in the engine: +Y (top), -Y (bottom),
## +X (east), -X (west), +Z (south, the "front"), -Z (north).
const FACE_COUNT := 6

var id := 0
var name := ""
## Atlas tile index for each face.
var tiles := PackedInt32Array([0, 0, 0, 0, 0, 0])
## Optional overlay tile per face (-1 = none), drawn over the base tile using
## its alpha. When a face has an overlay, the tint applies to the overlay only.
var overlays := PackedInt32Array([-1, -1, -1, -1, -1, -1])
## Color multiplier in sRGB (biome grass/foliage). White = no tint.
var tint := Color.WHITE
var layer: int = 0 # Blocks.Layer.OPAQUE
## Hide faces between two blocks of this same type (glass, water).
var cull_self := false

## Tick behavior (all optional), each called as f(world: VoxelWorld, pos: Vector3i):
## - random_tick: picked at random a few times per chunk per tick
##   (grass spreading, crops growing, leaves decaying).
## - scheduled_tick: when a tick requested with VoxelWorld.schedule_tick()
##   comes due (falling sand, flowing water, redstone delays).
## - on_update: this block or one of its 6 neighbors changed
##   ("block update"); usually schedules a tick.
var random_tick := Callable()
var scheduled_tick := Callable()
var on_update := Callable()


## Same texture on every face.
static func cube(block_name: String, tile: int) -> BlockType:
	var block := BlockType.new()
	block.name = block_name
	block.tiles = PackedInt32Array([tile, tile, tile, tile, tile, tile])
	return block


## Logs, sandstone, grass: separate top / sides / bottom.
static func column(block_name: String, top: int, side: int, bottom: int = -1) -> BlockType:
	var block := BlockType.new()
	block.name = block_name
	block.tiles = PackedInt32Array([top, top if bottom < 0 else bottom, side, side, side, side])
	return block


## Blocks with a front face (+Z for now; orientation states come later).
static func with_front(block_name: String, top: int, bottom: int, front: int, side: int, back: int = -1) -> BlockType:
	var block := BlockType.new()
	block.name = block_name
	block.tiles = PackedInt32Array([top, bottom, side, side, front, side if back < 0 else back])
	return block


func set_layer(value: int) -> BlockType:
	layer = value
	return self


func set_tint(value: Color) -> BlockType:
	tint = value
	return self


func set_side_overlay(tile: int) -> BlockType:
	for face in range(2, FACE_COUNT):
		overlays[face] = tile
	return self


func set_cull_self(value: bool = true) -> BlockType:
	cull_self = value
	return self


func set_random_tick(handler: Callable) -> BlockType:
	random_tick = handler
	return self


func set_scheduled_tick(handler: Callable) -> BlockType:
	scheduled_tick = handler
	return self


func set_on_update(handler: Callable) -> BlockType:
	on_update = handler
	return self
