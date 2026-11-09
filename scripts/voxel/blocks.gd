class_name Blocks
extends RefCounted
## Block registry. A block is stored in chunks as a single byte (its id),
## so there can be up to 255 types plus air.
##
## To add a block: append a register() call in _register_all(). Ids are given
## in registration order, so always append at the end to keep ids stable
## (saved worlds will depend on them).
##
## Tile numbers refer to the 16x16 tile atlas (index = row * 16 + column).
## Replacing the atlas with custom art only requires updating these numbers.

enum Layer {
	OPAQUE,      ## Solid cube, hides neighbor faces.
	CUTOUT,      ## Fully transparent pixels cut out (glass, leaves).
	TRANSLUCENT, ## Alpha-blended (water).
}
const LAYER_COUNT := 3

const AIR := 0

const ATLAS_PATH := "res://assets/textures/terrain.png"
const ATLAS_TILES_PER_ROW := 16

## Biome tints (sRGB). Grass tops / grass side overlays and leaves are
## grayscale in the atlas and get colored by these.
const GRASS_PLAINS := Color("91bd59")
const GRASS_FOREST := Color("79c05a")
const GRASS_TAIGA := Color("86b783")
const GRASS_SWAMP := Color("6a7039")
const GRASS_SAVANNA := Color("bfb755")
const FOLIAGE_OAK := Color("59ae30")
const FOLIAGE_BIRCH := Color("80a755")
const FOLIAGE_SPRUCE := Color("619961")

static var types: Array[BlockType] = []
static var _ids_by_name := {}

# Flat per-id lookup tables for the mesher's hot loop (no object access).
static var is_opaque_table := PackedByteArray()
static var layer_table := PackedByteArray()
static var cull_self_table := PackedByteArray()
static var face_tiles := PackedInt32Array()    # [id * 6 + face]
static var face_overlays := PackedInt32Array() # [id * 6 + face], -1 = none
static var tints_linear := PackedColorArray()  # [id]
# 1 if the block has a random tick handler: lets the world skip others fast.
static var ticks_randomly := PackedByteArray()
# Light lost when passing through the block (0..15, see BlockType.light_opacity).
static var light_opacity_table := PackedByteArray()
## 1 if entities collide with the block (see BlockType.collides).
static var collides_table := PackedByteArray()
## 1 for liquids (see BlockType.liquid).
static var liquid_table := PackedByteArray()

static var _registered := _register_all()


static func _register_all() -> bool:
	register(BlockType.cube("air", 0).set_layer(Layer.TRANSLUCENT).set_collides(false).set_hardness(-1)) # id 0, never drawn

	# Terrain
	register(BlockType.cube("stone", 1).set_hardness(1.5).set_drop("cobblestone"))
	register(BlockType.cube("dirt", 2).set_hardness(0.5))
	register(_grass("grass_plains", GRASS_PLAINS))
	register(_grass("grass_forest", GRASS_FOREST))
	register(_grass("grass_taiga", GRASS_TAIGA))
	register(_grass("grass_swamp", GRASS_SWAMP))
	register(_grass("grass_savanna", GRASS_SAVANNA))
	register(BlockType.cube("cobblestone", 16).set_hardness(2.0))
	register(BlockType.cube("bedrock", 17).set_hardness(-1))
	register(_falling(BlockType.cube("sand", 18).set_hardness(0.5)))
	register(_falling(BlockType.cube("gravel", 19).set_hardness(0.6)))
	register(BlockType.column("sandstone", 176, 192, 208).set_hardness(0.8))
	register(BlockType.cube("obsidian", 37).set_hardness(10.0))
	# Still water on top and bottom, flowing water on the sides (both animated, WaterAnimation).
	register(BlockType.column("water", 205, 206).set_layer(Layer.TRANSLUCENT).set_cull_self().set_light_opacity(2) \
		.set_collides(false).set_hardness(-1).set_liquid())

	# Trees
	register(BlockType.column("oak_log", 21, 20).set_hardness(2.0))
	register(BlockType.column("birch_log", 21, 117).set_hardness(2.0))
	register(BlockType.column("spruce_log", 21, 116).set_hardness(2.0))
	register(BlockType.cube("oak_leaves", 52).set_layer(Layer.CUTOUT).set_tint(FOLIAGE_OAK).set_light_opacity(1) \
		.set_hardness(0.2).set_drop("none").set_fast_tile(53))
	register(BlockType.cube("birch_leaves", 52).set_layer(Layer.CUTOUT).set_tint(FOLIAGE_BIRCH).set_light_opacity(1) \
		.set_hardness(0.2).set_drop("none").set_fast_tile(53))
	register(BlockType.cube("spruce_leaves", 132).set_layer(Layer.CUTOUT).set_tint(FOLIAGE_SPRUCE).set_light_opacity(1) \
		.set_hardness(0.2).set_drop("none").set_fast_tile(133))
	register(BlockType.cube("oak_planks", 4).set_hardness(2.0))
	register(BlockType.cube("birch_planks", 214).set_hardness(2.0))
	register(BlockType.cube("spruce_planks", 198).set_hardness(2.0))

	# Ores and mineral blocks
	register(BlockType.cube("coal_ore", 34).set_hardness(3.0))
	register(BlockType.cube("iron_ore", 33).set_hardness(3.0))
	register(BlockType.cube("gold_ore", 32).set_hardness(3.0))
	register(BlockType.cube("lapis_ore", 160).set_hardness(3.0))
	register(BlockType.cube("diamond_ore", 50).set_hardness(3.0))
	register(BlockType.cube("redstone_ore", 51).set_hardness(3.0))
	register(BlockType.cube("iron_block", 22).set_hardness(5.0))
	register(BlockType.cube("gold_block", 23).set_hardness(3.0))
	register(BlockType.cube("lapis_block", 144).set_hardness(3.0))
	register(BlockType.cube("diamond_block", 24).set_hardness(5.0))

	# Building
	register(BlockType.cube("glass", 49).set_layer(Layer.CUTOUT).set_cull_self().set_hardness(0.3).set_drop("none"))
	for wool: Array in [
		["white", 64], ["orange", 210], ["magenta", 194], ["light_blue", 178],
		["yellow", 162], ["lime", 146], ["pink", 130], ["gray", 114],
		["light_gray", 225], ["cyan", 209], ["purple", 193], ["blue", 177],
		["brown", 161], ["green", 145], ["red", 129], ["black", 113],
	]:
		register(BlockType.cube("%s_wool" % wool[0], wool[1]).set_hardness(0.8))

	# Workstations (front faces +Z until blocks get orientation)
	register(BlockType.with_front("crafting_table", 43, 4, 59, 60).set_hardness(2.5))
	register(BlockType.with_front("furnace", 62, 62, 44, 45).set_hardness(3.5))

	# Cold biomes (appended: ids must stay stable)
	register(BlockType.column("snowy_grass", 66, 68, 2).set_hardness(0.6).set_drop("dirt"))
	register(BlockType.cube("snow", 66).set_hardness(0.2))
	register(BlockType.cube("ice", 67).set_layer(Layer.TRANSLUCENT).set_cull_self().set_light_opacity(2) \
		.set_hardness(0.5).set_slipperiness(0.98).set_drop("none"))
	return true


static func _grass(block_name: String, tint: Color) -> BlockType:
	# Top: grayscale grass tinted. Sides: dirt-based tile + tinted grass fringe.
	return BlockType.column(block_name, 0, 3, 2).set_side_overlay(38).set_tint(tint) \
		.set_hardness(0.6).set_drop("dirt").set_random_tick(Callable(GrassBehavior, "random_tick"))


## Sand, gravel: fall when the block below is air or water.
static func _falling(block: BlockType) -> BlockType:
	return block.set_on_update(Callable(FallingBlockBehavior, "on_update")) \
		.set_scheduled_tick(Callable(FallingBlockBehavior, "scheduled_tick"))


static func register(block: BlockType) -> int:
	var id := types.size()
	assert(id < 256, "Block ids are stored as bytes: at most 256 types.")
	assert(not _ids_by_name.has(block.name), "Duplicate block name: " + block.name)
	block.id = id
	types.append(block)
	_ids_by_name[block.name] = id

	is_opaque_table.append(1 if block.layer == Layer.OPAQUE and id != AIR else 0)
	layer_table.append(block.layer)
	cull_self_table.append(1 if block.cull_self else 0)
	face_tiles.append_array(block.tiles)
	face_overlays.append_array(block.overlays)
	tints_linear.append(block.tint.srgb_to_linear())
	ticks_randomly.append(1 if block.random_tick.is_valid() else 0)
	if block.light_opacity < 0:
		block.light_opacity = 15 if is_opaque_table[id] == 1 else 0
	light_opacity_table.append(block.light_opacity)
	collides_table.append(1 if block.collides else 0)
	liquid_table.append(1 if block.liquid else 0)
	return id


static func id_of(block_name: String) -> int:
	assert(_ids_by_name.has(block_name), "Unknown block: " + block_name)
	return _ids_by_name[block_name]


static func count() -> int:
	return types.size()


## True if the block fully hides the faces of its neighbors (and casts AO).
static func is_opaque(id: int) -> bool:
	return is_opaque_table[id] == 1


static func get_type(id: int) -> BlockType:
	return types[id]


## Block given when `id` is broken in survival; AIR = nothing.
static func drop_of(id: int) -> int:
	var drop := types[id].drop
	if drop == "":
		return id
	if drop == "none":
		return AIR
	return id_of(drop)


## Display name ("oak_planks" -> "Oak Planks").
static func display_name(id: int) -> String:
	return Lang.t(types[id].name.capitalize())


static var _fast_graphics := false


## Fast graphics: blocks with a fast tile (leaves) become opaque with that
## tile, Fancy: back to cutout. Returns true if anything changed (re-mesh).
static func set_fast_graphics(fast: bool) -> bool:
	if fast == _fast_graphics:
		return false
	_fast_graphics = fast
	for block in types:
		if block.fast_tile < 0:
			continue
		var id := block.id
		var opaque := fast
		is_opaque_table[id] = 1 if opaque else 0
		layer_table[id] = Layer.OPAQUE if opaque else block.layer
		for face in BlockType.FACE_COUNT:
			face_tiles[id * BlockType.FACE_COUNT + face] = block.fast_tile if fast else block.tiles[face]
	return true
