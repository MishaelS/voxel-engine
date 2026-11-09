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
## Biome tint kind per block (see BlockType.biome_tint).
static var biome_tint_table := PackedByteArray()
## Random texture variants per block (BlockType.Rotation).
static var random_rotation_table := PackedByteArray()
## Top height per block (see BlockType.height).
static var height_table := PackedFloat32Array()
## Texture turn per face [id * 6 + face] (see BlockType.uv_modes).
static var uv_mode_table := PackedInt32Array()
## Cull group per block (see BlockType.cull_group).
static var cull_group_table := PackedInt32Array()
## Liquid level per block, -1 = not a liquid (see BlockType.liquid_level).
static var liquid_level_table := PackedInt32Array()
## Facing per block (-1 = not oriented).
static var facing_table := PackedInt32Array()
## Shape per block (BlockType.Shape).
static var shape_table := PackedByteArray()
## 1 for blocks that placing or flowing liquids replace (plants).
static var replaceable_table := PackedByteArray()
## family -> [ids by facing] (or [id] for blocks without facing).
static var _families := {}

static var _registered := _register_all()


static func _register_all() -> bool:
	register(BlockType.cube("air", 0).set_layer(Layer.TRANSLUCENT).set_collides(false).set_hardness(-1)) # id 0, never drawn

	# Terrain
	register(BlockType.cube("stone", 1).set_random_rotation(BlockType.Rotation.MIRROR).set_hardness(1.5).set_drop("cobblestone").set_tool("pickaxe", 0))
	register(BlockType.cube("dirt", 2).set_random_rotation().set_hardness(0.5).set_tool("shovel"))
	register(_grass("grass_plains", GRASS_PLAINS))
	register(_grass("grass_forest", GRASS_FOREST))
	register(_grass("grass_taiga", GRASS_TAIGA))
	register(_grass("grass_swamp", GRASS_SWAMP))
	register(_grass("grass_savanna", GRASS_SAVANNA))
	register(BlockType.cube("cobblestone", 16).set_hardness(2.0).set_tool("pickaxe", 0))
	register(BlockType.cube("bedrock", 17).set_random_rotation(BlockType.Rotation.MIRROR).set_hardness(-1))
	register(_falling(BlockType.cube("sand", 18).set_random_rotation().set_hardness(0.5).set_tool("shovel")))
	register(_falling(BlockType.cube("gravel", 19).set_hardness(0.6).set_tool("shovel") \
		.set_drops([{"item": "flint", "chance": 0.1}, {"item": "gravel"}])))
	register(BlockType.column("sandstone", 176, 192, 208).set_hardness(0.8).set_tool("pickaxe", 0))
	register(BlockType.cube("obsidian", 37).set_hardness(10.0).set_tool("pickaxe", 3))
	# Still water on top and bottom, flowing water on the sides (both animated, WaterAnimation).
	register(_liquid("water", 0).set_item("water"))

	# Trees
	register(BlockType.column("oak_log", 21, 20).set_hardness(2.0).set_tool("axe"))
	register(BlockType.column("birch_log", 21, 117).set_hardness(2.0).set_tool("axe"))
	register(BlockType.column("spruce_log", 21, 116).set_hardness(2.0).set_tool("axe"))
	register(BlockType.cube("oak_leaves", 52).set_layer(Layer.CUTOUT).set_tint(FOLIAGE_OAK).set_light_opacity(1) \
		.set_hardness(0.2).set_drops(_leaf_drops("oak", true)).set_biome_tint(2).set_fast_tile(53) \
		.set_on_update(Callable(LeafBehavior, "on_update")).set_scheduled_tick(Callable(LeafBehavior, "scheduled_tick")))
	register(BlockType.cube("birch_leaves", 52).set_layer(Layer.CUTOUT).set_tint(FOLIAGE_BIRCH).set_light_opacity(1) \
		.set_hardness(0.2).set_drops(_leaf_drops("birch", false)).set_fast_tile(53) \
		.set_on_update(Callable(LeafBehavior, "on_update")).set_scheduled_tick(Callable(LeafBehavior, "scheduled_tick")))
	register(BlockType.cube("spruce_leaves", 132).set_layer(Layer.CUTOUT).set_tint(FOLIAGE_SPRUCE).set_light_opacity(1) \
		.set_hardness(0.2).set_drops(_leaf_drops("spruce", false)).set_fast_tile(133) \
		.set_on_update(Callable(LeafBehavior, "on_update")).set_scheduled_tick(Callable(LeafBehavior, "scheduled_tick")))
	register(BlockType.cube("oak_planks", 4).set_hardness(2.0).set_tool("axe"))
	register(BlockType.cube("birch_planks", 214).set_hardness(2.0).set_tool("axe"))
	register(BlockType.cube("spruce_planks", 198).set_hardness(2.0).set_tool("axe"))

	# Ores and mineral blocks
	register(BlockType.cube("coal_ore", 34).set_hardness(3.0).set_tool("pickaxe", 0).set_drops([{"item": "coal"}]))
	register(BlockType.cube("iron_ore", 33).set_hardness(3.0).set_tool("pickaxe", 1))
	register(BlockType.cube("gold_ore", 32).set_hardness(3.0).set_tool("pickaxe", 2))
	register(BlockType.cube("lapis_ore", 160).set_hardness(3.0).set_tool("pickaxe", 1))
	register(BlockType.cube("diamond_ore", 50).set_hardness(3.0).set_tool("pickaxe", 2).set_drops([{"item": "diamond"}]))
	register(BlockType.cube("redstone_ore", 51).set_hardness(3.0).set_tool("pickaxe", 2).set_drops([{"item": "redstone", "min": 4, "max": 5}]))
	register(BlockType.cube("iron_block", 22).set_hardness(5.0).set_tool("pickaxe", 1))
	register(BlockType.cube("gold_block", 23).set_hardness(3.0).set_tool("pickaxe", 2))
	register(BlockType.cube("lapis_block", 144).set_hardness(3.0).set_tool("pickaxe", 1))
	register(BlockType.cube("diamond_block", 24).set_hardness(5.0).set_tool("pickaxe", 2))

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
	register(BlockType.with_front("crafting_table", 43, 4, 59, 60).set_hardness(2.5).set_tool("axe"))
	register(_furnace("furnace", 44, 0))

	# Cold biomes (appended: ids must stay stable)
	register(BlockType.column("snowy_grass", 66, 68, 2).set_hardness(0.6).set_drop("dirt").set_tool("shovel"))
	register(BlockType.cube("snow", 66).set_hardness(0.2).set_tool("shovel", 0) \
		.set_drops([{"item": "snowball", "min": 4, "max": 4}]))
	register(BlockType.cube("ice", 67).set_layer(Layer.TRANSLUCENT).set_cull_self().set_light_opacity(2) \
		.set_hardness(0.5).set_slipperiness(0.98).set_drop("none").set_tool("pickaxe"))

	# Oriented variants, containers, flowing water and beds (appended: ids stay stable).
	for facing in range(1, 4):
		register(_furnace("furnace", 44, facing))
	for facing in 4:
		register(_furnace("furnace_lit", 61, facing))
	for facing in 4:
		register(_chest(facing))
	for level in range(1, 9):
		register(_liquid("water_falling" if level == 8 else "water_%d" % level, level))
	for part in ["foot", "head"]:
		for facing in 4:
			register(_bed(part, facing))

	# Plants, lava and leaves placed by the player (appended: ids stay stable).
	register(BlockType.cube("tall_grass", 39).as_plant().set_tint(GRASS_PLAINS).set_biome_tint(1) \
		.set_drops([{"item": "seeds", "chance": 0.125}, {}]))
	register(BlockType.cube("fern", 56).as_plant().set_tint(GRASS_PLAINS).set_biome_tint(1) \
		.set_drops([{"item": "seeds", "chance": 0.125}, {}]))
	register(BlockType.cube("dead_bush", 55).as_plant().set_drop("none"))
	register(BlockType.cube("dandelion", 13).as_plant().set_height(0.6))
	register(BlockType.cube("rose", 12).as_plant().set_height(0.6))
	for level in range(0, 9):
		var lava_name := "lava" if level == 0 else ("lava_falling" if level == 8 else "lava_%d" % level)
		register(_liquid(lava_name, level, "lava"))
	for leaves: String in ["oak", "birch", "spruce"]:
		var placed := Blocks.get_type(id_of(leaves + "_leaves")).duplicate_type(leaves + "_leaves_placed")
		placed.item = leaves + "_leaves"
		placed.in_catalog = false
		placed.on_update = Callable()
		placed.scheduled_tick = Callable()
		types[id_of(leaves + "_leaves")].placed_as = placed.name
		register(placed)
	for sapling: Array in [["oak", 15], ["birch", 79], ["spruce", 63]]:
		var block := BlockType.cube(sapling[0] + "_sapling", sapling[1]).as_plant() \
			.set_random_tick(Callable(SaplingBehavior, "random_tick"))
		block.replaceable = false # placing a block next to it doesn't remove it
		register(block)
	return true


## Leaves drop like the classic game: a sapling of their tree 1 time in 20,
## oak leaves also an apple 1 time in 200 (both can happen), else nothing
## (shears are not in the game yet).
static func _leaf_drops(tree: String, apple: bool) -> Array:
	var drops := [{"item": tree + "_sapling", "chance": 0.05, "also": true}]
	if apple:
		drops.append({"item": "apple", "chance": 0.005, "also": true})
	return drops


const FACING_NAMES: Array[String] = ["south", "west", "north", "east"]
## Front / back face index for each facing (faces: +Y, -Y, +X, -X, +Z, -Z).
const FRONT_FACE: Array[int] = [4, 3, 5, 2]
const BACK_FACE: Array[int] = [5, 2, 4, 3]
## Direction of each facing.
const FACING_DIRECTIONS: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0)]


## An oriented cube: `front` on the facing side, `side` elsewhere around.
static func _oriented(family: String, facing: int, top: int, bottom: int, front: int, side: int) -> BlockType:
	var block_name := family if facing == 0 else "%s_%s" % [family, FACING_NAMES[facing]]
	var block := BlockType.column(block_name, top, side, bottom)
	block.tiles[FRONT_FACE[facing]] = front
	block.family = family
	block.facing = facing
	if facing != 0:
		block.item = family
		block.in_catalog = false
	return block


static func _furnace(family: String, front: int, facing: int) -> BlockType:
	var block := _oriented(family, facing, 62, 62, front, 45).set_hardness(3.5).set_tool("pickaxe", 0)
	if family == "furnace_lit":
		block.item = "furnace"
		block.in_catalog = false
	return block


static func _chest(facing: int) -> BlockType:
	return _oriented("chest", facing, 27, 27, 189, 42).set_hardness(2.5).set_tool("axe")


## Water or lava: still (level 0, the source) or flowing (1..7 lower and
## lower, 8 falling); see LiquidBehavior. Water is translucent and lets
## some light through; lava is opaque, glows (always full bright) and
## blocks sky light.
static func _liquid(block_name: String, level: int, family: String = "water") -> BlockType:
	var block: BlockType
	if family == "lava":
		block = BlockType.column(block_name, 237, 238).set_cull_self().set_light_opacity(15)
		block.emissive = true
	else:
		block = BlockType.column(block_name, 205, 206).set_layer(Layer.TRANSLUCENT).set_cull_self().set_light_opacity(2)
	block.set_collides(false).set_hardness(-1).set_liquid().set_drop("none") \
		.set_on_update(Callable(LiquidBehavior, "on_update")) \
		.set_scheduled_tick(Callable(LiquidBehavior, "scheduled_tick"))
	block.liquid_level = level
	block.family = family
	if level > 0:
		block.item = family
		block.in_catalog = false
	return block


## Half of a bed (9/16 high): the foot or the head, facing from foot to head.
## Textures like the classic game: the bed runs along the textures' u axis
## with the head toward +u, so faces are turned / mirrored to match.
static func _bed(part: String, facing: int) -> BlockType:
	var head := part == "head"
	var block := BlockType.cube("bed_%s_%s" % [part, FACING_NAMES[facing]], 4).set_height(0.5625) \
		.set_hardness(0.2).set_item("bed").set_cull_self().hidden_from_catalog()
	block.family = "bed_" + part
	block.facing = facing
	var direction := FACING_DIRECTIONS[facing]
	block.tiles[0] = 135 if head else 134
	# Top face: u runs along +X; quarter turns make it run along the facing.
	block.uv_modes[0] = [3, 2, 1, 0][facing]
	# u direction of each side face (+X, -X, +Z, -Z faces).
	var u_directions := {2: Vector3i(0, 0, -1), 3: Vector3i(0, 0, 1), 4: Vector3i(1, 0, 0), 5: Vector3i(-1, 0, 0)}
	for face in range(2, 6):
		var normal: Vector3i = ChunkMesher.FACE_OFFSETS[face]
		if normal == direction:
			block.tiles[face] = 152 # the head end
		elif normal == -direction:
			block.tiles[face] = 149 # the foot end
		else:
			block.tiles[face] = 151 if head else 150
			if u_directions[face] != direction:
				block.uv_modes[face] = 4
	return block


static func _grass(block_name: String, tint: Color) -> BlockType:
	# Top: grayscale grass tinted. Sides: dirt-based tile + tinted grass fringe.
	return BlockType.column(block_name, 0, 3, 2).set_side_overlay(38).set_tint(tint).set_random_rotation() \
		.set_hardness(0.6).set_drop("dirt").set_biome_tint(1).set_random_tick(Callable(GrassBehavior, "random_tick"))


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

	is_opaque_table.append(1 if block.layer == Layer.OPAQUE and id != AIR and block.height >= 1.0 and not block.liquid else 0)
	if block.emissive:
		block.overlays = PackedInt32Array([-2, -2, -2, -2, -2, -2]) # full bright (block shaders)
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
	random_rotation_table.append(block.random_rotation)
	height_table.append(block.height)
	uv_mode_table.append_array(block.uv_modes)
	liquid_level_table.append(block.liquid_level)
	facing_table.append(block.facing)
	shape_table.append(block.shape)
	replaceable_table.append(1 if block.replaceable else 0)
	var family := block.family if block.family != "" else block.name
	if not _families.has(family):
		_families[family] = []
		if block.cull_self:
			block.cull_group = id # the first of a family is its group
	elif block.cull_self:
		block.cull_group = types[(_families[family] as Array)[0]].cull_group
	(_families[family] as Array).append(id)
	if block.family.begins_with("bed_"):
		# Both halves of a bed hide the faces between them.
		block.cull_group = id_of("bed_foot_south") if _ids_by_name.has("bed_foot_south") else id
	cull_group_table.append(block.cull_group if block.cull_group >= 0 else id)
	biome_tint_table.append(block.biome_tint)
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


## Item a block counts as (state variants -> their base block or item):
## what pick block gives and what its name is.
static func item_of(id: int) -> int:
	var item := types[id].item
	return id if item == "" else Items.id_of(item)


## Items dropped when `id` is broken in survival, like the classic game:
## [[item id, count], ...]. `can_harvest` = the right tool was used (blocks
## that need a tool drop nothing without it).
static func drops_of(id: int, rng: RandomNumberGenerator, can_harvest: bool = true) -> Array:
	var block := types[id]
	if not can_harvest or block.drop == "none":
		return []
	if block.drop != "":
		return [[id_of(block.drop), 1]]
	if block.drops.is_empty():
		return [[item_of(id), 1]]
	var result := []
	for entry: Dictionary in block.drops:
		if entry.is_empty():
			break
		if rng.randf() >= entry.get("chance", 1.0):
			continue
		var count := rng.randi_range(entry.get("min", 1), entry.get("max", entry.get("min", 1)))
		result.append([Items.id_of(entry.item), count])
		if not entry.get("also", false):
			break # the first that drops (gravel: flint or gravel)
	return result


## The block of `family` with `facing` (0 south, 1 west, 2 north, 3 east).
static func variant(family: String, facing: int = 0) -> int:
	var ids: Array = _families.get(family, [])
	if ids.is_empty():
		return AIR
	return ids[clampi(facing, 0, ids.size() - 1)]


## All blocks of a family (facings, levels), in registration order.
static func family_ids(family: String) -> Array:
	return _families.get(family, [])


static func family_of(id: int) -> String:
	var block := types[id]
	return block.family if block.family != "" else block.name


## The facing a placed block gets so that its front looks at the player
## (the player looking along `look`), like the classic game.
static func facing_toward(look: Vector3) -> int:
	if absf(look.x) > absf(look.z):
		return 3 if look.x < 0.0 else 1 # looking west: front faces east
	return 0 if look.z < 0.0 else 2


## Display name ("oak_planks" -> "Oak Planks"); variants use their item's.
static func display_name(id: int) -> String:
	return Items.display_name(item_of(id))


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
