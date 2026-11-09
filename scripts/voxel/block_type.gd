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
## How much light the block takes away when light passes through it:
## 0 = clear (air, glass), 1 = leaves, 2 = water / ice, 15 = blocks light.
## -1 = derived from the render layer (opaque blocks 15, others 0).
var light_opacity := -1
## Seconds-ish toughness like the classic game: breaking by hand takes
## hardness * 1.5 seconds in survival. -1 = unbreakable (bedrock, water).
var hardness := 1.0
## Whether entities (the player) collide with it. Off for air and liquids.
var collides := true
## Ground friction factor (0.6 normal, 0.98 ice: entities slide).
var slipperiness := 0.6
## What breaking it gives in survival: "" = the block itself, "none" =
## nothing, otherwise a block name (stone -> cobblestone).
var drop := ""
## Liquids (water) hide their faces toward other translucent blocks (ice
## on water), like the classic game.
var liquid := false
## Tile used with Fast graphics (-1 = none): the block is then drawn opaque
## with this tile, like the classic game's fast leaves.
var fast_tile := -1

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


func set_light_opacity(value: int) -> BlockType:
	light_opacity = value
	return self


func set_hardness(value: float) -> BlockType:
	hardness = value
	return self


func set_collides(value: bool) -> BlockType:
	collides = value
	return self


func set_slipperiness(value: float) -> BlockType:
	slipperiness = value
	return self


func set_drop(block_name: String) -> BlockType:
	drop = block_name
	return self


func set_fast_tile(tile: int) -> BlockType:
	fast_tile = tile
	return self


func set_liquid(value: bool = true) -> BlockType:
	liquid = value
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
