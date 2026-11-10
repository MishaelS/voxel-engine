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
## Color from the climate of its block column instead of `tint` (in the
## world): 0 = none, 1 = grass color, 2 = foliage color. Like the classic
## game's color maps: colors change smoothly across biomes.
var biome_tint := 0
## Random texture variants like the modern game's block states, the same
## for the same block position (Random Texture Rotation setting), so large
## areas of one block don't show a repeating pattern:
## - TURN (dirt, grass, sand): the block is turned by a random multiple of
##   90 degrees around the vertical axis: the top texture turns, the sides
##   look the same;
## - MIRROR (stone, bedrock): mirrored and / or turned by 180 degrees, so
##   the texture's grain keeps its direction.
enum Rotation { NONE, TURN, MIRROR }
var random_rotation: int = Rotation.NONE
## Item this block counts as (drops, pick block, names): "" = itself.
## State variants (facings, lit furnace, flowing water, bed halves) name
## their base block or item here.
var item := ""
## Height of the block's top (1 = full cube; the bed is 9/16). Blocks lower
## than 1 never hide their neighbors' faces.
var height := 1.0
## Texture turn per face (bits 0-1: quarter turns of the UVs, bit 2: mirror
## left-right), for oriented textures (beds).
var uv_modes := PackedInt32Array([0, 0, 0, 0, 0, 0])
## Blocks of the same cull group hide faces between them when cull_self is
## set (water and flowing water, the two bed halves). -1 = the block itself.
var cull_group := -1
## Listed in the creative catalog (state variants are not).
var in_catalog := true
## Tool that breaks it fast ("pickaxe", "shovel", "axe", "" = none) and
## the tool tier needed to get its drops (-1 = anything, even the hand;
## 0 = wood, 1 = stone, 2 = iron, 3 = diamond), like the classic game.
var tool := ""
var harvest_level := -1
## What breaking it gives, like the classic game: entries tried in order,
## the first whose chance roll succeeds is dropped (entries with "also"
## drop besides the others). Each entry is {"item": name, "chance": 0..1,
## "min": n, "max": n, "also": bool}. Empty = the block's item; [{}] (an
## empty entry) or "none" in set_drop = nothing.
var drops: Array = []
## Liquid level like the classic game: 0 = source, 1..7 = flowing (lower
## and lower), 8 = falling; -1 = not a liquid.
var liquid_level := -1
## Facing of oriented blocks: 0 = south (+Z), 1 = west, 2 = north, 3 =
## east (-1 = not oriented); `family` groups the facings and states.
var facing := -1
var family := ""
## Shape: CUBE, CROSS (two crossed squares: tall grass, flowers) or CHEST
## (the chest model, ChestModel; `chest_part`: single or a large chest's half).
enum Shape { CUBE, CROSS, CHEST }
var chest_part := 0
var shape: int = Shape.CUBE
## Placing a block or pouring a liquid into it simply replaces it (plants).
var replaceable := false
## The block placed when the player places this one ("" = itself):
## leaves place a variant that never decays.
var placed_as := ""
## Shown at full brightness whatever the light (lava).
var emissive := false

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


## Drop entries (see `drops`).
func set_drops(entries: Array) -> BlockType:
	drops = entries
	return self


func set_item(item_name: String) -> BlockType:
	item = item_name
	return self


func set_height(value: float) -> BlockType:
	height = value
	return self


func set_tool(tool_kind: String, level: int = -1) -> BlockType:
	tool = tool_kind
	harvest_level = level
	return self


func set_uv_mode(face: int, mode: int) -> BlockType:
	uv_modes[face] = mode
	return self


## A copy with another name (state variants of an existing block).
func duplicate_type(new_name: String) -> BlockType:
	var copy := BlockType.new()
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(property.name, get(property.name))
	copy.name = new_name
	copy.id = 0
	copy.family = ""
	copy.cull_group = -1
	return copy


## A plant: two crossed squares, no collision, breaks at once, replaced
## by placed blocks and flowing liquids, needs the right ground below.
func as_plant() -> BlockType:
	shape = Shape.CROSS
	layer = 1 # Blocks.Layer.CUTOUT
	collides = false
	hardness = 0.0
	replaceable = true
	light_opacity = 0
	height = 0.8
	on_update = Callable(PlantBehavior, "on_update")
	return self


func hidden_from_catalog() -> BlockType:
	in_catalog = false
	return self


func set_biome_tint(kind: int) -> BlockType:
	biome_tint = kind
	return self


func set_random_rotation(value: int = Rotation.TURN) -> BlockType:
	random_rotation = value
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
