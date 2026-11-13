class_name Blocks
extends RefCounted
## Block registry. A block is stored in chunks as a 32-bit id (ChunkData);
## every state of a block (facing, level, half) is its own id.
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
## Block model per block (BlockModel index; Shape.MODEL), -1 = none.
static var model_table := PackedInt32Array()
## Chest part per block (ChestModel.Part; chests only).
static var chest_part_table := PackedByteArray()
## Collision boxes per block (Array[AABB], block units) and the outline box.
static var collision_table: Array = []
static var selection_table: Array[AABB] = []
## Per id: the boxes aimed at and outlined (outline_boxes, else the
## collision boxes when several, else the selection box).
static var outline_table: Array = []
## 1 if the block has display effects (BlockType.display_tick).
static var display_table := PackedByteArray()
## Light given off per block (BlockType.light_emission) and the ids that glow.
static var light_emission_table := PackedByteArray()
static var glowing_ids := PackedInt32Array()
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
	register(BlockType.cube("lapis_ore", 160).set_hardness(3.0).set_tool("pickaxe", 1)
		.set_drops([{"item": "lapis_lazuli", "min": 4, "max": 8}]))
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
	var ice := BlockType.cube("ice", 67).set_layer(Layer.TRANSLUCENT).set_cull_self().set_light_opacity(2) \
		.set_hardness(0.5).set_slipperiness(0.98).set_drop("none").set_tool("pickaxe")
	ice.random_tick = Callable(LiquidBehavior, "ice_random_tick") # melts near heat and in warm biomes
	register(ice)

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
	for half in ["chest_left", "chest_right"]:
		for facing in 4:
			register(_chest(facing, half))

	# Light and fire (appended: ids stay stable).
	register(_torch(-1))
	for facing in 4:
		register(_torch(facing))
	register(BlockType.cube("glowstone", 105).set_hardness(0.3).set_light_emission(15) \
		.set_drops([{"item": "glowstone_dust", "min": 2, "max": 4}]))
	for facing in 4:
		# Carved pumpkins (shears in crafting, see Crafting); worlds from before
		# keep theirs (same ids).
		register(_oriented("carved_pumpkin", facing, 102, 102, 119, 118).set_hardness(1.0).set_tool("axe"))
	for facing in 4:
		register(_oriented("jack_o_lantern", facing, 102, 102, 120, 118).set_hardness(1.0).set_tool("axe") \
			.set_light_emission(15))
	for age in FireBehavior.MAX_AGE + 1:
		register(_fire(age))
	_register_building_blocks()
	_register_nature()
	_register_farming()
	_register_dungeons()
	_register_music()
	_register_redstone()
	_register_rails()
	# A whole pumpkin, as it grows (appended: ids stay stable).
	register(BlockType.column("pumpkin", 102, 118, 102).set_hardness(1.0).set_tool("axe"))
	# A block being moved by a piston (PistonBehavior): shows nothing itself
	# (the moving block is drawn sliding over it), becomes that block when it
	# arrives.
	var moving := BlockType.cube("moving_piston", 0).set_hardness(-1).set_light_opacity(0).set_drop("none") \
		.set_collides(false).set_scheduled_tick(Callable(PistonBehavior, "finish_moving")).hidden_from_catalog()
	moving.layer = Layer.CUTOUT
	moving.shape = BlockType.Shape.MODEL
	moving.model = BlockModel.register([])
	register(moving)
	# Levers on ceilings, buttons on floors and ceilings: all six sides
	# (appended: ids stay stable).
	for place in [6, 7]:
		for on in [false, true]:
			register(_lever(place, on))
	for facing in [4, 5]:
		for pressed in [false, true]:
			register(_button(facing, pressed))
	_set_flammability()
	return true


# --- Rails (stage 11) ------------------------------------------------------------------

## Rails, powered rails and detector rails (RailBehavior) (appended: ids
## stay stable).
static func _register_rails() -> void:
	for shape in 10:
		register(_rail("rail", 128, 112, shape, false))
	for family: Array in [["powered_rail", 163, 179], ["detector_rail", 195, 195]]:
		for shape in 6:
			for on in [false, true]:
				register(_rail(family[0], family[2] if on else family[1], 0, shape, on))


## A rail: a flat picture on the ground (turned for east-west and curves), or
## a ramp up to the next block for slopes.
static func _rail(family: String, tile: int, curve_tile: int, shape: int, on: bool) -> BlockType:
	var index := shape if family == "rail" else shape * 2 + (1 if on else 0)
	var block := BlockType.cube(family if index == 0 else "%s_%d" % [family, index], tile).set_layer(Layer.CUTOUT) \
		.set_collides(false).set_hardness(0.7).set_light_opacity(0).set_height(0.125) \
		.set_on_update(Callable(RailBehavior, "on_update")).set_selection(AABB(Vector3.ZERO, Vector3(16, 2, 16)))
	block.family = family
	block.item = family
	block.in_catalog = index == 0
	block.flat_item = true
	block.shape = BlockType.Shape.MODEL
	if family == "detector_rail":
		block.scheduled_tick = Callable(RailBehavior, "detector_tick")
	var rising := RailBehavior.rising(shape)
	if rising != Vector3i.ZERO:
		# Written rising toward north (-Z), turned to its direction.
		var facing := (Blocks.FACING_DIRECTIONS.find(rising) + 2) % 4
		block.model = BlockModel.register([{"from": Vector3(0, 0, 16 - 16 * sqrt(2.0)), "to": Vector3(16, 1, 16),
			"faces": {BlockModel.UP: {"layer": tile, "uv": Rect2(0, 0, 16, 16)}},
			"rotation": {"axis": "x", "angle": 45.0, "origin": Vector3(8, 0, 16)}}], facing)
		block.set_selection(AABB(Vector3.ZERO, Vector3(16, 8, 16)))
	elif shape >= 6:
		block.model = BlockModel.register([{"from": Vector3(0, 0, 0), "to": Vector3(16, 1, 16),
			# The curve picture joins south and east (shape 6); our uv turns go
			# the other way round from the game's, so south-west and north-east
			# take 3 and 1 (they bulged the wrong way).
			"faces": {BlockModel.UP: {"layer": curve_tile, "uv_turn": [0, 3, 2, 1][shape - 6]}}}])
	else:
		block.model = BlockModel.register([{"from": Vector3(0, 0, 0), "to": Vector3(16, 1, 16),
			"faces": {BlockModel.UP: {"layer": tile, "uv_turn": shape}}}])
	return block


# --- Redstone (stage 10) -------------------------------------------------------------

## Pistons are written facing up and tilted into place (Redstone.DIRS order).
const PISTON_TURNS := [["x", 180.0], ["x", 0.0], ["x", -90.0], ["x", 90.0], ["z", 90.0], ["z", -90.0]]


## Wire, torches, levers, buttons, plates, repeaters, pistons, dispensers and
## glowing redstone ore (appended: ids stay stable). See Redstone.
static func _register_redstone() -> void:
	# Wire: 16 power levels x 81 shapes (Redstone.wire_shape).
	for power in 16:
		for shape in Redstone.SHAPES:
			register(_redstone_wire(power, shape))
	# Torches: lit and unlit, on the floor and on walls.
	for lit in [true, false]:
		register(_redstone_torch(-1, lit))
		for facing in 4:
			register(_redstone_torch(facing, lit))
	# Levers: on the floor along x / z, on walls; off and on.
	for place in 6:
		for on in [false, true]:
			register(_lever(place, on))
	for facing in 4:
		for pressed in [false, true]:
			register(_button(facing, pressed))
	for kind: Array in [["stone_pressure_plate", 1], ["wooden_pressure_plate", 4]]:
		for pressed in [false, true]:
			register(_pressure_plate(kind[0], kind[1], pressed))
	for facing in 4:
		for delay in range(1, 5):
			for powered in [false, true]:
				register(_repeater(facing, delay, powered))
	for sticky in [false, true]:
		for dir in 6:
			for extended in [false, true]:
				register(_piston(dir, extended, sticky))
	for dir in 6:
		for sticky in [false, true]:
			register(_piston_head(dir, sticky))
	for facing in 4:
		register(_oriented("dispenser", facing, 62, 62, 46, 45).set_hardness(3.5).set_tool("pickaxe", 0)
			.set_on_update(Callable(DispenserBehavior, "on_update"))
			.set_scheduled_tick(Callable(DispenserBehavior, "scheduled_tick")))
	var lit_ore := BlockType.cube("lit_redstone_ore", 51).set_hardness(3.0).set_tool("pickaxe", 2) \
		.set_drops([{"item": "redstone", "min": 4, "max": 5}]).set_light_emission(9) \
		.set_random_tick(Callable(RedstoneOre, "random_tick")).set_display_tick(Callable(RedstoneOre, "display_tick")) \
		.hidden_from_catalog()
	lit_ore.item = "redstone_ore"
	register(lit_ore)
	# Doors, trapdoors, TNT and note blocks react to power too.
	for block in types:
		var family := family_of(block.id)
		if family in ["trapdoor", "trapdoor_open", "note_block", "tnt"] or DoorBehavior.is_door(block.id):
			if block.on_update.is_valid() and block.on_update != Callable(Redstone, "consumer_update"):
				Redstone.inner_updates[family] = block.on_update
			block.on_update = Callable(Redstone, "consumer_update")


## Wire color by power, like the game's.
static func _wire_color(power: int) -> Color:
	var f := power / 15.0
	var r := f * 0.6 + 0.4 if power > 0 else 0.3
	return Color(r, maxf(f * f * 0.7 - 0.5, 0.0), maxf(f * f * 0.6 - 0.7, 0.0))


static func _redstone_wire(power: int, shape: int) -> BlockType:
	var index := power * Redstone.SHAPES + shape
	var block := BlockType.cube("redstone_wire" if index == 0 else "redstone_wire_%d" % index, 164) \
		.set_layer(Layer.CUTOUT).set_collides(false).set_hardness(0.0).set_light_opacity(0).set_height(0.0625) \
		.set_drops([{"item": "redstone"}]).set_tint(_wire_color(power)) \
		.set_on_update(Callable(Redstone, "on_wire_update")).set_selection(AABB(Vector3.ZERO, Vector3(16, 1, 16)))
	block.family = "redstone_wire"
	block.item = "redstone"
	block.in_catalog = false
	block.shape = BlockType.Shape.MODEL
	var sides: Array[int] = []
	var rest := shape
	for i in 4:
		sides.append(rest % 3)
		rest /= 3
	# HORIZONTAL order: south (+Z), west (-X), north (-Z), east (+X).
	var south := sides[0] != 0
	var west := sides[1] != 0
	var north := sides[2] != 0
	var east := sides[3] != 0
	var boxes := []
	if not (south or west or north or east):
		boxes.append({"from": Vector3(0, 0, 0), "to": Vector3(16, 0.25, 16), "faces": {BlockModel.UP: {"layer": 164}}})
	elif not (west or east):
		boxes.append({"from": Vector3(0, 0, 0), "to": Vector3(16, 0.25, 16), "faces": {BlockModel.UP: {"layer": 165, "uv_turn": 1}}})
	elif not (south or north):
		boxes.append({"from": Vector3(0, 0, 0), "to": Vector3(16, 0.25, 16), "faces": {BlockModel.UP: {"layer": 165}}})
	else:
		var from := Vector3(0.0 if west else 5.0, 0, 0.0 if north else 5.0)
		var to := Vector3(16.0 if east else 11.0, 0.25, 16.0 if south else 11.0)
		boxes.append({"from": from, "to": to, "faces": {BlockModel.UP: {"layer": 164}}})
	# Up the side of a block: a line on its face.
	var walls := [
		[Vector3(0, 0, 15.75), Vector3(16, 16, 16), BlockModel.NORTH],
		[Vector3(0, 0, 0), Vector3(0.25, 16, 16), BlockModel.EAST],
		[Vector3(0, 0, 0), Vector3(16, 16, 0.25), BlockModel.SOUTH],
		[Vector3(15.75, 0, 0), Vector3(16, 16, 16), BlockModel.WEST],
	]
	for i in 4:
		if sides[i] == 2:
			var wall: Array = walls[i]
			boxes.append({"from": wall[0], "to": wall[1], "faces": {wall[2]: {"layer": 165, "uv": Rect2(0, 0, 16, 16), "uv_turn": 1}}})
	block.model = BlockModel.register(boxes)
	return block


static func _redstone_torch(facing: int, lit: bool) -> BlockType:
	var on_wall := facing >= 0
	var family := ("" if lit else "unlit_") + ("redstone_wall_torch" if on_wall else "redstone_torch")
	var tile := 99 if lit else 115
	var block := BlockType.cube(family if facing <= 0 else "%s_%s" % [family, FACING_NAMES[facing]], tile) \
		.set_layer(Layer.CUTOUT).set_collides(false).set_hardness(0.0).set_light_opacity(0) \
		.set_light_emission(7 if lit else 0).set_height(0.625) \
		.set_on_update(Callable(RedstoneComponents, "on_torch_update")) \
		.set_scheduled_tick(Callable(RedstoneComponents, "torch_tick"))
	if lit:
		block.display_tick = Callable(RedstoneComponents, "torch_display_tick")
	block.flat_item = true
	block.shape = BlockType.Shape.MODEL
	block.family = family
	block.item = "redstone_torch"
	block.in_catalog = family == "redstone_torch"
	var faces := {
		BlockModel.UP: {"layer": tile, "uv": Rect2(7, 6, 2, 2)},
		BlockModel.DOWN: {"layer": tile, "uv": Rect2(7, 13, 2, 2)},
	}
	for side in [BlockModel.EAST, BlockModel.WEST, BlockModel.SOUTH, BlockModel.NORTH]:
		faces[side] = {"layer": tile, "uv": Rect2(7, 6, 2, 10)}
	if on_wall:
		block.facing = facing
		block.model = BlockModel.register([{"from": Vector3(7, 3.5, -1), "to": Vector3(9, 13.5, 1), "faces": faces,
			"rotation": {"axis": "x", "angle": 22.5, "origin": Vector3(8, 3.5, 0)}}], facing)
		block.set_selection(_facing_box(AABB(Vector3(5.5, 3, 0), Vector3(5, 10, 5)), facing))
	else:
		block.model = BlockModel.register([{"from": Vector3(7, 0, 7), "to": Vector3(9, 10, 9), "faces": faces}])
		block.set_selection(AABB(Vector3(6, 0, 6), Vector3(4, 10, 4)))
	return block


static func _all_faces(tile: int) -> Dictionary:
	var faces := {}
	for face in 6:
		faces[face] = {"layer": tile}
	return faces


## A lever (`place`: 0 floor along x, 1 floor along z, 2..5 on a wall facing
## place - 2, 6 / 7 on the ceiling along x / z): a cobblestone base and a
## stick leaning one way or the other.
static func _lever(place: int, on: bool) -> BlockType:
	var index := place * 2 + (1 if on else 0)
	var block := BlockType.cube("lever" if index == 0 else "lever_%d" % index, 16).set_layer(Layer.CUTOUT) \
		.set_collides(false).set_hardness(0.5).set_light_opacity(0) \
		.set_on_update(Callable(RedstoneComponents, "on_attached_update"))
	block.family = "lever"
	block.item = "lever"
	block.in_catalog = index == 0
	block.flat_item = false
	block.shape = BlockType.Shape.MODEL
	var stick := {
		BlockModel.UP: {"layer": 96, "uv": Rect2(7, 6, 2, 2)}, BlockModel.DOWN: {"layer": 96, "uv": Rect2(7, 14, 2, 2)},
		BlockModel.EAST: {"layer": 96, "uv": Rect2(7, 6, 2, 10)}, BlockModel.WEST: {"layer": 96, "uv": Rect2(7, 6, 2, 10)},
		BlockModel.SOUTH: {"layer": 96, "uv": Rect2(7, 6, 2, 10)}, BlockModel.NORTH: {"layer": 96, "uv": Rect2(7, 6, 2, 10)},
	}
	var tilt := -40.0 if on else 40.0
	if place >= 6:
		# Hanging from the ceiling: the floor lever upside down.
		var along_x := place == 6
		var base := {"from": Vector3(4, 13, 5) if along_x else Vector3(5, 13, 4),
			"to": Vector3(12, 16, 11) if along_x else Vector3(11, 16, 12), "faces": _all_faces(16)}
		var lever := {"from": Vector3(7, 5, 7), "to": Vector3(9, 15, 9), "faces": stick,
			"rotation": {"axis": "z" if along_x else "x", "angle": -tilt, "origin": Vector3(8, 15, 8)}}
		block.model = BlockModel.register([base, lever])
		block.set_selection(AABB(Vector3(4, 6, 4), Vector3(8, 10, 8)))
		block.in_catalog = false
	elif place < 2:
		var along_x := place == 0
		var base := {"from": Vector3(4, 0, 5) if along_x else Vector3(5, 0, 4),
			"to": Vector3(12, 3, 11) if along_x else Vector3(11, 3, 12), "faces": _all_faces(16)}
		var lever := {"from": Vector3(7, 1, 7), "to": Vector3(9, 11, 9), "faces": stick,
			"rotation": {"axis": "z" if along_x else "x", "angle": tilt, "origin": Vector3(8, 1, 8)}}
		block.model = BlockModel.register([base, lever])
		block.set_selection(AABB(Vector3(4, 0, 4), Vector3(8, 10, 8)))
	else:
		var base := {"from": Vector3(5, 4, 0), "to": Vector3(11, 12, 3), "faces": _all_faces(16)}
		var lever := {"from": Vector3(7, 8, 1), "to": Vector3(9, 18, 3), "faces": stick,
			"rotation": {"axis": "x", "angle": 90.0 + tilt, "origin": Vector3(8, 8, 2)}}
		block.facing = place - 2
		block.model = BlockModel.register([base, lever], place - 2)
		block.set_selection(_facing_box(AABB(Vector3(4, 3, 0), Vector3(8, 10, 8)), place - 2))
	return block


## A box (pixels) turned around the block's middle like a facing.
static func _facing_box(box: AABB, facing: int) -> AABB:
	var basis := Basis(Vector3.UP, deg_to_rad(BlockModel.FACING_TURNS[facing]))
	var middle := Vector3(8, 8, 8)
	var result := AABB(basis * (box.position - middle) + middle, Vector3.ZERO)
	for i in 8:
		result = result.expand(basis * (box.get_endpoint(i) - middle) + middle)
	return result


static func _button(facing: int, pressed: bool) -> BlockType:
	var index := facing * 2 + (1 if pressed else 0)
	var block := BlockType.cube("stone_button" if index == 0 else "stone_button_%d" % index, 1).set_layer(Layer.CUTOUT) \
		.set_collides(false).set_hardness(0.5).set_light_opacity(0) \
		.set_on_update(Callable(RedstoneComponents, "on_attached_update")) \
		.set_scheduled_tick(Callable(RedstoneComponents, "button_tick"))
	block.family = "stone_button"
	block.item = "stone_button"
	block.in_catalog = index == 0
	block.shape = BlockType.Shape.MODEL
	var depth := 1.0 if pressed else 2.0
	if facing >= 4:
		# 4: on the floor, 5: on the ceiling.
		var low := 0.0 if facing == 4 else 16.0 - depth
		block.model = BlockModel.register([{"from": Vector3(5, low, 6), "to": Vector3(11, low + depth, 10),
			"faces": _all_faces(1)}])
		block.set_selection(AABB(Vector3(5, low, 6), Vector3(6, depth, 4)))
		return block
	block.facing = facing
	block.model = BlockModel.register([{"from": Vector3(5, 6, 0), "to": Vector3(11, 10, depth), "faces": _all_faces(1)}], facing)
	block.set_selection(_facing_box(AABB(Vector3(5, 6, 0), Vector3(6, 4, depth)), facing))
	return block


static func _pressure_plate(family: String, tile: int, pressed: bool) -> BlockType:
	var block := BlockType.cube(family if not pressed else family + "_pressed", tile).set_layer(Layer.CUTOUT) \
		.set_collides(false).set_hardness(0.5).set_light_opacity(0).set_height(0.0625) \
		.set_on_update(Callable(RedstoneComponents, "on_plate_update")) \
		.set_scheduled_tick(Callable(RedstoneComponents, "plate_tick"))
	block.family = family
	block.item = family
	block.in_catalog = not pressed
	block.shape = BlockType.Shape.MODEL
	if tile == 4:
		block.set_tool("axe")
	else:
		block.set_tool("pickaxe", 0)
	var height := 0.5 if pressed else 1.0
	block.model = BlockModel.register([{"from": Vector3(1, 0, 1), "to": Vector3(15, height, 15), "faces": _all_faces(tile)}])
	block.set_selection(AABB(Vector3(1, 0, 1), Vector3(14, height, 14)))
	return block


## A repeater facing its output (+Z when written): a slab with the redstone
## channel, a fixed torch near the output and a torch further back the
## longer the delay.
static func _repeater(facing: int, delay: int, powered: bool) -> BlockType:
	var index := ((facing * 4 + delay - 1) * 2) + (1 if powered else 0)
	var top := 147 if powered else 131
	var torch := 99 if powered else 115
	var block := BlockType.cube("repeater" if index == 0 else "repeater_%d" % index, top).set_layer(Layer.CUTOUT) \
		.set_hardness(0.0).set_light_opacity(0).set_height(0.125) \
		.set_on_update(Callable(RedstoneComponents, "on_repeater_update")) \
		.set_scheduled_tick(Callable(RedstoneComponents, "repeater_tick")) \
		.set_collision([AABB(Vector3.ZERO, Vector3(16, 2, 16))]).set_selection(AABB(Vector3.ZERO, Vector3(16, 2, 16)))
	block.family = "repeater"
	block.item = "repeater"
	block.in_catalog = index == 0
	block.facing = facing
	block.shape = BlockType.Shape.MODEL
	var torch_faces := {BlockModel.UP: {"layer": torch, "uv": Rect2(7, 6, 2, 2)}}
	for side in [BlockModel.EAST, BlockModel.WEST, BlockModel.SOUTH, BlockModel.NORTH]:
		torch_faces[side] = {"layer": torch, "uv": Rect2(7, 6, 2, 5)}
	var slab := {BlockModel.UP: {"layer": top}, BlockModel.DOWN: {"layer": 6}}
	for side in [BlockModel.EAST, BlockModel.WEST, BlockModel.SOUTH, BlockModel.NORTH]:
		slab[side] = {"layer": 5}
	var back := 8.0 - (delay - 1) * 2.0
	block.model = BlockModel.register([
		{"from": Vector3(0, 0, 0), "to": Vector3(16, 2, 16), "faces": slab},
		{"from": Vector3(7, 2, 11), "to": Vector3(9, 7, 13), "faces": torch_faces},
		{"from": Vector3(7, 2, back - 1), "to": Vector3(9, 7, back + 1), "faces": torch_faces},
	], facing)
	return block


## Boxes (pixels) of a piston part pointing up, tilted to `dir`.
static func _piston_boxes(boxes: Array, dir: int) -> Array:
	var turn: Array = PISTON_TURNS[dir]
	if turn[1] == 0.0:
		return boxes
	for box: Dictionary in boxes:
		box["rotation"] = {"axis": turn[0], "angle": turn[1], "origin": Vector3(8, 8, 8)}
	return boxes


## A box (pixels) pointing up, turned to `dir` like _piston_boxes.
static func _piston_box(box: AABB, dir: int) -> AABB:
	var turn: Array = PISTON_TURNS[dir]
	var basis := Basis(Vector3.RIGHT if turn[0] == "x" else Vector3.BACK, deg_to_rad(turn[1]))
	var middle := Vector3(8, 8, 8)
	var result := AABB(basis * (box.position - middle) + middle, Vector3.ZERO)
	for i in 8:
		result = result.expand(basis * (box.get_endpoint(i) - middle) + middle)
	return result


static func _piston(dir: int, extended: bool, sticky: bool) -> BlockType:
	var family := "sticky_piston" if sticky else "piston"
	var index := dir * 2 + (1 if extended else 0)
	var front := 106 if sticky else 107
	var block := BlockType.cube(family if index == 0 else "%s_%d" % [family, index], 108).set_hardness(0.5) \
		.set_on_update(Callable(PistonBehavior, "on_update")) \
		.set_scheduled_tick(Callable(PistonBehavior, "scheduled_tick"))
	block.family = family
	block.item = family
	block.in_catalog = index == 2 # the one facing north, like an item
	block.shape = BlockType.Shape.MODEL
	var sides := {BlockModel.DOWN: {"layer": 109}}
	for side in [BlockModel.EAST, BlockModel.WEST, BlockModel.SOUTH, BlockModel.NORTH]:
		sides[side] = {"layer": 108}
	if extended:
		sides[BlockModel.UP] = {"layer": 110}
		block.model = BlockModel.register(_piston_boxes([{"from": Vector3(0, 0, 0), "to": Vector3(16, 12, 16), "faces": sides}], dir))
		var box := _piston_box(AABB(Vector3.ZERO, Vector3(16, 12, 16)), dir)
		# The head's arm reaches 4 pixels into the base: aimed at too.
		var arm := _piston_box(AABB(Vector3(6, 12, 6), Vector3(4, 4, 4)), dir)
		block.set_collision([box, arm]).set_selection(box)
	else:
		sides[BlockModel.UP] = {"layer": front}
		block.model = BlockModel.register(_piston_boxes([{"from": Vector3(0, 0, 0), "to": Vector3(16, 16, 16), "faces": sides}], dir))
	return block


static func _piston_head(dir: int, sticky: bool) -> BlockType:
	var index := dir * 2 + (1 if sticky else 0)
	var front := 106 if sticky else 107
	var block := BlockType.cube("piston_head" if index == 0 else "piston_head_%d" % index, 108).set_hardness(0.5) \
		.set_light_opacity(0).set_drop("none").set_on_update(Callable(PistonBehavior, "on_head_update")).hidden_from_catalog()
	block.family = "piston_head"
	block.shape = BlockType.Shape.MODEL
	var plate := {BlockModel.UP: {"layer": front}, BlockModel.DOWN: {"layer": 107}}
	for side in [BlockModel.EAST, BlockModel.WEST, BlockModel.SOUTH, BlockModel.NORTH]:
		plate[side] = {"layer": 108}
	var arm := {}
	for side in [BlockModel.EAST, BlockModel.WEST, BlockModel.SOUTH, BlockModel.NORTH]:
		arm[side] = {"layer": 108, "uv": Rect2(0, 0, 16, 4), "uv_turn": 1}
	block.model = BlockModel.register(_piston_boxes([
		{"from": Vector3(0, 12, 0), "to": Vector3(16, 16, 16), "faces": plate},
		{"from": Vector3(6, -4, 6), "to": Vector3(10, 12, 10), "faces": arm},
	], dir))
	var plate_box := _piston_box(AABB(Vector3(0, 12, 0), Vector3(16, 4, 16)), dir)
	var arm_box := _piston_box(AABB(Vector3(6, 0, 6), Vector3(4, 12, 4)), dir)
	block.set_collision([plate_box, arm_box]).set_selection(plate_box.merge(arm_box))
	return block


# --- Music (stage 8) -----------------------------------------------------------------

## Note blocks and jukeboxes (MusicBehavior) (appended: ids stay stable).
static func _register_music() -> void:
	register(BlockType.cube("note_block", 74).set_hardness(0.8).set_tool("axe"))
	register(BlockType.column("jukebox", 75, 74).set_hardness(2.0).set_tool("axe"))
	# TNT (PrimedTnt): breaks at once; breaking, fire or an explosion light it.
	register(BlockType.column("tnt", 9, 8, 10).set_hardness(0.0))


# --- Dungeons (stage 6) --------------------------------------------------------------

## Mob spawners (one per mob) and the dungeon chest marker (appended: ids
## stay stable).
static func _register_dungeons() -> void:
	for mob: String in DungeonBehavior.SPAWNER_TYPES:
		var spawner := BlockType.cube("mob_spawner_" + mob, 65).set_layer(Layer.CUTOUT).set_light_opacity(0) \
			.set_hardness(5.0).set_tool("pickaxe", 0).set_drop("none")
		spawner.display_tick = Callable(DungeonBehavior, "spawner_display_tick")
		spawner.family = "mob_spawner"
		register(spawner)
	var chest := _chest(0)
	chest.name = "dungeon_chest"
	chest.family = "dungeon_chest"
	chest.item = "chest"
	chest.in_catalog = false
	chest.display_tick = Callable(DungeonBehavior, "chest_display_tick")
	register(chest)


# --- Farming (stage 5) ---------------------------------------------------------------

## Farmland (dry, wet), wheat (8 stages) and cake (6 slices) (appended: ids
## stay stable).
static func _register_farming() -> void:
	for wet in [false, true]:
		var farmland := BlockType.column("farmland_wet" if wet else "farmland", 86 if wet else 87, 2, 2) \
			.set_height(0.9375).set_hardness(0.6).set_tool("shovel").set_drop("dirt") \
			.set_on_update(Callable(FarmBehavior, "on_update")).set_random_tick(Callable(FarmBehavior, "random_tick")) \
			.set_collision([AABB(Vector3.ZERO, Vector3(16, 16, 16))]).set_selection(AABB(Vector3.ZERO, Vector3(16, 15, 16)))
		# Like the game: drawn 15/16 high but solid all the way up, so nothing
		# sinks in when it is trampled back into (full) dirt.
		farmland.family = "farmland"
		if wet:
			farmland.in_catalog = false
		register(farmland)
	for stage in 8:
		var wheat := BlockType.cube("wheat_crop" if stage == 0 else "wheat_crop_%d" % stage, 88 + stage).set_layer(Layer.CUTOUT) \
			.set_collides(false).set_hardness(0.0).set_light_opacity(0).set_height(0.25 + stage * 0.1).set_item("seeds") \
			.set_on_update(Callable(FarmBehavior, "on_update")).set_random_tick(Callable(FarmBehavior, "random_tick")) \
			.hidden_from_catalog()
		wheat.family = "wheat_crop"
		# Ripe: wheat and up to 3 seeds; before that sometimes a seed back.
		wheat.drops = [{"item": "wheat", "also": true}, {"item": "seeds", "min": 0, "max": 3}] if stage == 7 \
			else [{"item": "seeds", "chance": 0.2}, {}]
		# Crops like the game: four planes in a # shape.
		var tile := 88 + stage
		wheat.shape = BlockType.Shape.MODEL
		wheat.model = BlockModel.register([
			{"from": Vector3(4, -1, 0), "to": Vector3(4, 15, 16), "faces": {BlockModel.EAST: {"layer": tile}, BlockModel.WEST: {"layer": tile}}},
			{"from": Vector3(12, -1, 0), "to": Vector3(12, 15, 16), "faces": {BlockModel.EAST: {"layer": tile}, BlockModel.WEST: {"layer": tile}}},
			{"from": Vector3(0, -1, 4), "to": Vector3(16, 15, 4), "faces": {BlockModel.SOUTH: {"layer": tile}, BlockModel.NORTH: {"layer": tile}}},
			{"from": Vector3(0, -1, 12), "to": Vector3(16, 15, 12), "faces": {BlockModel.SOUTH: {"layer": tile}, BlockModel.NORTH: {"layer": tile}}},
		])
		register(wheat)
	for eaten in 6:
		var cake := BlockType.cube("cake" if eaten == 0 else "cake_%d" % eaten, 121).set_hardness(0.5).set_drop("none") \
			.set_height(0.999).set_light_opacity(0).set_item("cake").set_on_update(Callable(FarmBehavior, "on_update")) \
			.hidden_from_catalog()
		cake.family = "cake"
		var from := Vector3(1 + 2 * eaten, 0, 1)
		var to := Vector3(15, 8, 15)
		cake.shape = BlockType.Shape.MODEL
		cake.model = BlockModel.register([{"from": from, "to": to, "faces": {
			BlockModel.UP: {"layer": 121}, BlockModel.DOWN: {"layer": 124},
			BlockModel.EAST: {"layer": 122}, BlockModel.SOUTH: {"layer": 122}, BlockModel.NORTH: {"layer": 122},
			BlockModel.WEST: {"layer": 123 if eaten > 0 else 122},
		}}])
		cake.collision_boxes.append(AABB(from / 16.0, (to - from) / 16.0))
		register(cake)


# --- Nature (stage 4) ----------------------------------------------------------------

## Cactus, sugar cane, mushrooms and springs (appended: ids stay stable).
static func _register_nature() -> void:
	var cactus := BlockType.column("cactus", 69, 70, 71).set_layer(Layer.CUTOUT).set_hardness(0.4) \
		.set_height(0.999).set_light_opacity(0).set_on_update(Callable(NatureBehavior, "on_update")) \
		.set_random_tick(Callable(NatureBehavior, "random_tick")) \
		.set_collision([AABB(Vector3(1, 0, 1), Vector3(14, 15, 14))]).set_selection(AABB(Vector3(1, 0, 1), Vector3(14, 16, 14)))
	cactus.shape = BlockType.Shape.MODEL
	# Like the game's: the top and bottom fill the block, each side is the
	# whole texture moved 1 pixel in (so the spines stick out at the edges).
	cactus.model = BlockModel.register([
		{"from": Vector3(0, 16, 0), "to": Vector3(16, 16, 16), "faces": {BlockModel.UP: {"layer": 69}}},
		{"from": Vector3(0, 0, 0), "to": Vector3(16, 0, 16), "faces": {BlockModel.DOWN: {"layer": 71}}},
		{"from": Vector3(15, 0, 0), "to": Vector3(15, 16, 16), "faces": {BlockModel.EAST: {"layer": 70}}},
		{"from": Vector3(1, 0, 0), "to": Vector3(1, 16, 16), "faces": {BlockModel.WEST: {"layer": 70}}},
		{"from": Vector3(0, 0, 15), "to": Vector3(16, 16, 15), "faces": {BlockModel.SOUTH: {"layer": 70}}},
		{"from": Vector3(0, 0, 1), "to": Vector3(16, 16, 1), "faces": {BlockModel.NORTH: {"layer": 70}}},
	])
	register(cactus)
	var reeds := BlockType.cube("sugar_cane_block", 73).as_plant().set_item("sugar_cane") \
		.set_on_update(Callable(NatureBehavior, "on_update")).set_random_tick(Callable(NatureBehavior, "random_tick")) \
		.hidden_from_catalog()
	reeds.replaceable = false
	reeds.height = 1.0
	register(reeds)
	for mushroom: Array in [["brown_mushroom", 29, 1], ["red_mushroom", 28, 0]]:
		var block := BlockType.cube(mushroom[0], mushroom[1]).as_plant().set_height(0.4) \
			.set_light_emission(mushroom[2]).set_on_update(Callable(NatureBehavior, "on_update")) \
			.set_random_tick(Callable(NatureBehavior, "random_tick"))
		block.replaceable = false
		register(block)
	for family: String in ["water", "lava"]:
		var spring := _liquid(family + "_spring", 0, family).hidden_from_catalog()
		spring.display_tick = Callable(NatureBehavior, "spring_display_tick")
		register(spring)


# --- Building blocks (stage 3) ------------------------------------------------------

const STAIR_MATERIALS := [["cobblestone", 16], ["oak", 4], ["birch", 214], ["spruce", 198]]
## Slabs: [name, top tile, side tile, bottom tile].
const SLAB_MATERIALS := [["stone", 6, 5, 6], ["sandstone", 176, 192, 208], ["wooden", 4, 4, 4], ["cobblestone", 16, 16, 16]]
const FENCE_DIRECTIONS: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0)]


## Stairs, slabs, fences, ladders, doors, trapdoors, signs, bricks, clay,
## bookshelves, mossy cobblestone, sponge, cobwebs, snow layers (appended:
## ids stay stable).
static func _register_building_blocks() -> void:
	for material: Array in STAIR_MATERIALS:
		for facing in 4:
			register(_stairs(material[0], material[1], facing))
	for material: Array in SLAB_MATERIALS:
		register(BlockType.column(material[0] + "_slab", material[1], material[2], material[3]).set_height(0.5) \
			.set_hardness(2.0 if material[0] != "wooden" else 2.0).set_tool("pickaxe" if material[0] != "wooden" else "axe",
				0 if material[0] != "wooden" else -1))
	for material: Array in SLAB_MATERIALS:
		register(BlockType.column("double_" + material[0] + "_slab", material[1], material[2], material[3]) \
			.set_hardness(2.0).set_tool("pickaxe" if material[0] != "wooden" else "axe", 0 if material[0] != "wooden" else -1) \
			.set_drops([{"item": material[0] + "_slab", "min": 2, "max": 2}]).hidden_from_catalog())
	for mask in 16:
		register(_fence(mask))
	for facing in 4:
		register(_ladder(facing))
	for kind: Array in [["wooden", 81, 97], ["iron", 82, 98]]:
		for half in ["lower", "upper"]:
			for state in ["closed", "open"]:
				for facing in 4:
					register(_door(kind[0], kind[1] if half == "upper" else kind[2], half, state == "open", facing))
	for state in ["closed", "open"]:
		for facing in 4:
			register(_trapdoor(state == "open", facing))
	for rotation in 16:
		register(_sign(rotation, -1))
	for facing in 4:
		register(_sign(-1, facing))
	register(BlockType.cube("bricks", 7).set_hardness(2.0).set_tool("pickaxe", 0))
	register(BlockType.cube("clay", 72).set_hardness(0.6).set_tool("shovel") \
		.set_drops([{"item": "clay_ball", "min": 4, "max": 4}]))
	register(BlockType.column("bookshelf", 4, 35).set_hardness(1.5).set_tool("axe") \
		.set_drops([{"item": "book", "min": 3, "max": 3}]))
	register(BlockType.cube("mossy_cobblestone", 36).set_hardness(2.0).set_tool("pickaxe", 0))
	register(BlockType.cube("sponge", 48).set_hardness(0.6))
	var web := BlockType.cube("cobweb", 11).as_plant().set_hardness(4.0).set_tool("sword", 0) \
		.set_drops([{"item": "string"}])
	web.replaceable = false
	web.height = 1.0
	web.on_update = Callable()
	register(web)
	var snow_layer := BlockType.cube("snow_layer", 66).set_height(0.125).set_collides(false).set_hardness(0.1) \
		.set_tool("shovel", 0).set_drops([{"item": "snowball"}]).set_on_update(Callable(TorchBehavior, "on_update_layer"))
	snow_layer.replaceable = true
	register(snow_layer)


static func _stairs(material: String, tile: int, facing: int) -> BlockType:
	var family := material + "_stairs"
	var block := BlockType.cube(family if facing == 0 else "%s_%s" % [family, FACING_NAMES[facing]], tile) \
		.set_hardness(2.0).set_tool("pickaxe" if material == "cobblestone" else "axe", 0 if material == "cobblestone" else -1) \
		.set_height(0.999).set_light_opacity(0)
	# Like Beta, stairs give back their material.
	block.drops = [{"item": "cobblestone" if material == "cobblestone" else material + "_planks"}]
	block.family = family
	block.facing = facing
	if facing != 0:
		block.item = family
		block.in_catalog = false
	# Facing south: the low step in front (+Z), the high part behind.
	var faces := {}
	for face in 6:
		faces[face] = {"layer": tile}
	var boxes := [
		{"from": Vector3(0, 0, 0), "to": Vector3(16, 8, 16), "faces": faces},
		{"from": Vector3(0, 8, 0), "to": Vector3(16, 16, 8), "faces": faces},
	]
	block.shape = BlockType.Shape.MODEL
	block.model = BlockModel.register(boxes, facing)
	var turn := Basis(Vector3.UP, deg_to_rad(BlockModel.FACING_TURNS[facing]))
	for box: Array in [[Vector3(0, 0, 0), Vector3(16, 8, 16)], [Vector3(0, 8, 0), Vector3(16, 16, 8)]]:
		block.collision_boxes.append(_turned_box(box[0] / 16.0, box[1] / 16.0, turn))
	block.selection_box = AABB(Vector3.ZERO, Vector3.ONE)
	return block


## A box (block units) turned around the block's vertical middle.
static func _turned_box(from: Vector3, to: Vector3, turn: Basis) -> AABB:
	var middle := Vector3(0.5, 0.0, 0.5)
	var a := turn * (from - middle) + middle
	var b := turn * (to - middle) + middle
	return AABB(a.min(b), (a - b).abs())


## A fence post with rails to the fences around (`mask` bits: south, west,
## north, east). Collides 1.5 blocks high like the game.
static func _fence(mask: int) -> BlockType:
	var block := BlockType.cube("fence" if mask == 0 else "fence_%d" % mask, 4).set_hardness(2.0).set_tool("axe") \
		.set_height(0.999).set_light_opacity(0).set_on_update(Callable(FenceBehavior, "on_update"))
	# Not a full block: the post and a bar to each neighbor it joins, aimed
	# at and outlined as they are; bumped into 1.5 blocks high (nothing jumps
	# over a fence), like the modern game's.
	var outline := [AABB(Vector3(6, 0, 6), Vector3(4, 16, 4))]
	var collision := [AABB(Vector3(6, 0, 6), Vector3(4, 24, 4))]
	for d in 4:
		if mask & (1 << d) == 0:
			continue
		var bar: AABB = [AABB(Vector3(7, 6, 10), Vector3(2, 9, 6)), AABB(Vector3(0, 6, 7), Vector3(6, 9, 2)),
			AABB(Vector3(7, 6, 0), Vector3(2, 9, 6)), AABB(Vector3(10, 6, 7), Vector3(6, 9, 2))][d]
		outline.append(bar)
		collision.append(AABB(Vector3(bar.position.x, 0, bar.position.z), Vector3(bar.size.x, 24, bar.size.z)))
	block.set_collision(collision).set_outline(outline)
	block.family = "fence"
	if mask != 0:
		block.item = "fence"
		block.in_catalog = false
	var faces := {}
	for face in 6:
		faces[face] = {"layer": 4}
	var boxes := [{"from": Vector3(6, 0, 6), "to": Vector3(10, 16, 10), "faces": faces}]
	for d in 4:
		if mask & (1 << d) == 0:
			continue
		for rail: Vector2 in [Vector2(12, 15), Vector2(6, 9)]:
			var from := Vector3(7, rail.x, 10)
			var to := Vector3(9, rail.y, 16)
			match d:
				1: # west
					from = Vector3(0, rail.x, 7)
					to = Vector3(6, rail.y, 9)
				2: # north
					from = Vector3(7, rail.x, 0)
					to = Vector3(9, rail.y, 6)
				3: # east
					from = Vector3(10, rail.x, 7)
					to = Vector3(16, rail.y, 9)
			boxes.append({"from": from, "to": to, "faces": faces})
	block.shape = BlockType.Shape.MODEL
	block.model = BlockModel.register(boxes)
	return block


## A ladder on the wall behind it (facing away from the wall): one flat
## picture, climbable, 2/16 thick.
static func _ladder(facing: int) -> BlockType:
	var block := BlockType.cube("ladder" if facing == 0 else "ladder_" + FACING_NAMES[facing], 83) \
		.set_layer(Layer.CUTOUT).set_hardness(0.4).set_tool("axe").set_height(0.999).set_light_opacity(0) \
		.set_on_update(Callable(TorchBehavior, "on_update"))
	block.family = "ladder"
	block.facing = facing
	block.climbable = true
	block.flat_item = true # its picture in the inventory, in hand and on the ground
	if facing != 0:
		block.item = "ladder"
		block.in_catalog = false
	block.shape = BlockType.Shape.MODEL
	block.model = BlockModel.register([{"from": Vector3(0, 0, 0.8), "to": Vector3(16, 16, 0.8),
		"faces": {BlockModel.SOUTH: {"layer": 83}}}], facing)
	var turn := Basis(Vector3.UP, deg_to_rad(BlockModel.FACING_TURNS[facing]))
	block.collision_boxes.append(_turned_box(Vector3(0, 0, 0), Vector3(1, 1, 0.125), turn))
	return block


## Half of a door (DoorBehavior): the panel 3/16 thick along the far side
## (facing south: the south edge), or swung open along the west edge.
static func _door(kind: String, tile: int, half: String, open: bool, facing: int) -> BlockType:
	var family := "%s_door_%s_%s" % [kind, half, "open" if open else "closed"]
	var block := BlockType.cube(family if facing == 0 else "%s_%s" % [family, FACING_NAMES[facing]], tile) \
		.set_layer(Layer.CUTOUT).set_hardness(3.0 if kind == "wooden" else 5.0) \
		.set_tool("axe" if kind == "wooden" else "pickaxe", -1 if kind == "wooden" else 0) \
		.set_height(0.999).set_light_opacity(0).set_on_update(Callable(DoorBehavior, "on_update")).hidden_from_catalog()
	block.family = family
	block.facing = facing
	block.item = kind + "_door"
	block.drops = [{"item": kind + "_door"}] if half == "lower" else [{}]
	var from := Vector3(0, 0, 13) if not open else Vector3(0, 0, 0)
	var to := Vector3(16, 16, 16) if not open else Vector3(3, 16, 16)
	var faces := {}
	for face in 6:
		faces[face] = {"layer": tile}
	# The back is mirrored, like the game's, so the hinges stay on one edge
	# (x = 0, where the door swings open) seen from either side.
	faces[BlockModel.WEST if open else BlockModel.NORTH]["mirror_u"] = true
	block.shape = BlockType.Shape.MODEL
	block.model = BlockModel.register([{"from": from, "to": to, "faces": faces}], facing)
	var turn := Basis(Vector3.UP, deg_to_rad(BlockModel.FACING_TURNS[facing]))
	block.collision_boxes.append(_turned_box(from / 16.0, to / 16.0, turn))
	return block


## A trapdoor hinged on the wall behind it (facing away from the wall):
## lying flat at the bottom, or standing up against the wall when open.
static func _trapdoor(open: bool, facing: int) -> BlockType:
	var family := "trapdoor_open" if open else "trapdoor"
	var block := BlockType.cube(family if facing == 0 else "%s_%s" % [family, FACING_NAMES[facing]], 84) \
		.set_layer(Layer.CUTOUT).set_hardness(3.0).set_tool("axe").set_height(0.999).set_light_opacity(0) \
		.set_on_update(Callable(TorchBehavior, "on_update"))
	block.family = family
	block.facing = facing
	if open or facing != 0:
		block.item = "trapdoor"
		block.in_catalog = false
	var from := Vector3(0, 0, 0)
	var to := Vector3(16, 3, 16) if not open else Vector3(16, 16, 3)
	var faces := {}
	for face in 6:
		faces[face] = {"layer": 84}
	block.shape = BlockType.Shape.MODEL
	block.model = BlockModel.register([{"from": from, "to": to, "faces": faces}], facing)
	var turn := Basis(Vector3.UP, deg_to_rad(BlockModel.FACING_TURNS[facing]))
	block.collision_boxes.append(_turned_box(from / 16.0, to / 16.0, turn))
	return block


## A sign: on the floor (`rotation` 0..15, every 22.5 degrees, facing the
## player who placed it) or on a wall (`facing`). The text is in its block
## entity (SignBehavior). No collision.
static func _sign(rotation: int, facing: int) -> BlockType:
	var on_wall := facing >= 0
	var block_name := ("sign" if rotation == 0 else "sign_%d" % rotation) if not on_wall \
		else ("wall_sign" if facing == 0 else "wall_sign_" + FACING_NAMES[facing])
	var block := BlockType.cube(block_name, 4).set_collides(false).set_hardness(1.0).set_tool("axe") \
		.set_height(0.999).set_light_opacity(0).set_item("sign").hidden_from_catalog()
	block.family = "wall_sign" if on_wall else "sign"
	block.facing = facing
	if not on_wall:
		block.on_update = Callable(SignBehavior, "on_update")
	else:
		block.on_update = Callable(TorchBehavior, "on_update")
	var faces := {}
	for face in 6:
		faces[face] = {"layer": 4}
	block.shape = BlockType.Shape.MODEL
	if on_wall:
		block.model = BlockModel.register([{"from": Vector3(0, 4.5, 0), "to": Vector3(16, 12.5, 1.33), "faces": faces}], facing)
		var turn := Basis(Vector3.UP, deg_to_rad(BlockModel.FACING_TURNS[facing]))
		block.selection_box = _turned_box(Vector3(0, 4.5, 0) / 16.0, Vector3(16, 12.5, 1.33) / 16.0, turn)
	else:
		block.model = BlockModel.register_turned([
			{"from": Vector3(0, 8, 7.33), "to": Vector3(16, 16, 8.67), "faces": faces},
			{"from": Vector3(7.33, 0, 7.33), "to": Vector3(8.67, 8, 8.67), "faces": faces},
		], -rotation * 22.5)
		block.selection_box = AABB(Vector3(0.25, 0, 0.25), Vector3(0.5, 1, 0.5))
	return block


## A torch: on the floor (facing -1) or on a wall (facing away from it,
## leaning 22.5 degrees), like the game's torch models; light 14.
static func _torch(facing: int) -> BlockType:
	var on_wall := facing >= 0
	var block_name := "torch" if not on_wall else ("wall_torch" if facing == 0 else "wall_torch_" + FACING_NAMES[facing])
	var block := BlockType.cube(block_name, 80).set_layer(Layer.CUTOUT).set_collides(false).set_hardness(0.0) \
		.set_light_opacity(0).set_light_emission(14).set_height(0.625) \
		.set_on_update(Callable(TorchBehavior, "on_update")).set_display_tick(Callable(TorchBehavior, "display_tick"))
	block.flat_item = true
	block.shape = BlockType.Shape.MODEL
	var faces := {
		BlockModel.UP: {"layer": 80, "uv": Rect2(7, 6, 2, 2)},
		BlockModel.DOWN: {"layer": 80, "uv": Rect2(7, 13, 2, 2)},
	}
	for side in [BlockModel.EAST, BlockModel.WEST, BlockModel.SOUTH, BlockModel.NORTH]:
		faces[side] = {"layer": 80, "uv": Rect2(7, 6, 2, 10)}
	if on_wall:
		block.family = "wall_torch"
		block.facing = facing
		block.item = "torch"
		block.in_catalog = false
		block.model = BlockModel.register([{"from": Vector3(7, 3.5, -1), "to": Vector3(9, 13.5, 1), "faces": faces,
			"rotation": {"axis": "x", "angle": 22.5, "origin": Vector3(8, 3.5, 0)}}], facing)
		block.set_selection(_facing_box(AABB(Vector3(5.5, 3, 0), Vector3(5, 10, 5)), facing))
	else:
		block.model = BlockModel.register([{"from": Vector3(7, 0, 7), "to": Vector3(9, 10, 9), "faces": faces}])
		block.set_selection(AABB(Vector3(6, 0, 6), Vector3(4, 10, 4)))
	return block


## Fire of an age 0..15 (FireBehavior): crossed burning pictures, glowing.
static func _fire(age: int) -> BlockType:
	var block := BlockType.cube("fire" if age == 0 else "fire_%d" % age, 31).as_plant().set_drop("none") \
		.set_light_emission(15).set_on_update(Callable(FireBehavior, "on_update")) \
		.set_scheduled_tick(Callable(FireBehavior, "scheduled_tick")) \
		.set_display_tick(Callable(FireBehavior, "display_tick")).hidden_from_catalog()
	block.emissive = true
	block.height = 1.0
	block.family = "fire"
	return block


## Which blocks burn, like the classic game (spread encouragement, burn
## chance): planks 5 / 20, logs 5 / 5, leaves and wool 30 / 60, tall grass
## and flowers 60 / 100.
static func _set_flammability() -> void:
	for block in types:
		var n := block.name
		if n.ends_with("_planks"):
			block.set_flammable(5, 20)
		elif n.ends_with("_log"):
			block.set_flammable(5, 5)
		elif n.contains("_leaves") or n.ends_with("_wool"):
			block.set_flammable(30, 60)
		elif n in ["tall_grass", "fern", "dead_bush", "dandelion", "rose"]:
			block.set_flammable(60, 100)
		elif n == "tnt":
			block.set_flammable(15, 100)
		elif n == "bookshelf":
			block.set_flammable(30, 20) # like the game's


## The sound material of a block (BlockType.sound), from its kind.
static func _sound_material(block: BlockType) -> String:
	var n := block.name
	if block.liquid or n == "air" or n.begins_with("fire"):
		return ""
	if n.contains("glass") or n == "ice" or n == "glowstone":
		return "glass"
	if n.ends_with("_wool") or n == "cactus":
		return "cloth"
	for wood in ["_log", "_planks", "crafting_table", "chest", "bed_", "torch", "pumpkin", "jack_o_lantern"]:
		if n.contains(wood):
			return "wood"
	if n.contains("leaves") or n.begins_with("grass_") or n.ends_with("_sapling") or n == "snowy_grass" \
			or block.shape == BlockType.Shape.CROSS:
		return "grass"
	if n == "gravel" or n == "dirt":
		return "gravel"
	if n == "sand":
		return "sand"
	if n == "snow":
		return "snow"
	return "stone"


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
		block.light_emission = 13
		block.display_tick = Callable(VoxelWorld, "furnace_display_tick")
	return block


## A chest (the chest model, 14/16 high) or one half of a large chest
## ("chest_left" / "chest_right" families, ChestModel.Part).
static func _chest(facing: int, family: String = "chest") -> BlockType:
	var planks := ChestModel.particle_layer()
	var block := _oriented(family, facing, planks, planks, planks, planks).set_hardness(2.5).set_tool("axe") \
		.set_height(0.875).set_on_update(Callable(ChestBehavior, "on_update"))
	block.chest_part = {"chest": ChestModel.Part.SINGLE, "chest_left": ChestModel.Part.LEFT,
		"chest_right": ChestModel.Part.RIGHT}[family]
	block.shape = BlockType.Shape.MODEL
	block.model = ChestModel.model_index(block.chest_part, facing)
	if family != "chest":
		block.item = "chest"
		block.in_catalog = false
	return block


## Water or lava: still (level 0, the source) or flowing (1..7 lower and
## lower, 8 falling); see LiquidBehavior. Water is translucent and lets
## some light through; lava is opaque, glows (always full bright) and
## blocks sky light.
static func _liquid(block_name: String, level: int, family: String = "water") -> BlockType:
	var block: BlockType
	if family == "lava":
		block = BlockType.column(block_name, 237, 238).set_cull_self().set_light_opacity(15)
		block.emissive = true
		block.light_emission = 15
		block.random_tick = Callable(LiquidBehavior, "lava_random_tick")
		block.display_tick = Callable(LiquidBehavior, "lava_display_tick")
	else:
		block = BlockType.column(block_name, 205, 206).set_layer(Layer.TRANSLUCENT).set_cull_self().set_light_opacity(2)
		block.display_tick = Callable(LiquidBehavior, "water_display_tick")
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
	assert(id < 65536, "Block ids are kept below 65536 (saves and tables).")
	assert(not _ids_by_name.has(block.name), "Duplicate block name: " + block.name)
	block.id = id
	block.sound = _sound_material(block)
	types.append(block)
	_ids_by_name[block.name] = id

	is_opaque_table.append(1 if block.layer == Layer.OPAQUE and id != AIR and block.height >= 1.0 and not block.liquid \
		and block.shape == BlockType.Shape.CUBE else 0)
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
	chest_part_table.append(block.chest_part)
	model_table.append(block.model)
	display_table.append(1 if block.display_tick.is_valid() else 0)
	if block.collision_boxes.is_empty() and block.collides:
		block.collision_boxes.append(AABB(Vector3.ZERO, Vector3(1, block.height, 1)))
	if not block.collides:
		block.collision_boxes.clear()
	collision_table.append(block.collision_boxes)
	if block.selection_box.size == Vector3.ZERO:
		var bounds := AABB(Vector3.ZERO, Vector3(1, block.height, 1))
		if block.shape == BlockType.Shape.CROSS and not block.name.begins_with("wheat"):
			# Plants are picked by a narrower box, like the game's: flowers and
			# mushrooms 0.4 wide, grass, saplings and the rest 0.8.
			var inset := 0.3 if block.name in ["dandelion", "rose", "brown_mushroom", "red_mushroom"] else 0.1
			bounds = AABB(Vector3(inset, 0, inset), Vector3(1.0 - inset * 2.0, block.height, 1.0 - inset * 2.0))
		if not block.collision_boxes.is_empty():
			bounds = block.collision_boxes[0]
			for box in block.collision_boxes:
				bounds = bounds.merge(box)
		block.selection_box = bounds
	selection_table.append(block.selection_box)
	if not block.outline_boxes.is_empty():
		outline_table.append(block.outline_boxes)
	else:
		outline_table.append(block.collision_boxes if block.collision_boxes.size() > 1 else [block.selection_box])
	light_emission_table.append(block.light_emission)
	if block.light_emission > 0:
		glowing_ids.append(id)
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


## True if a point inside a block (0..1 local coordinates) is inside one of
## its collision boxes.
static func blocks_point(id: int, local: Vector3) -> bool:
	for box: AABB in collision_table[id]:
		if box.has_point(local):
			return true
	return false


## The top of the block's collision under a point (0..1 x / z), or -1.
static func top_at(id: int, local_x: float, local_z: float) -> float:
	var top := -1.0
	for box: AABB in collision_table[id]:
		if local_x >= box.position.x and local_x <= box.end.x and local_z >= box.position.z and local_z <= box.end.z:
			top = maxf(top, box.end.y)
	return top


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
	var item := item_of(id)
	if item == id and family_of(id) != types[id].name:
		return Lang.t(family_of(id).capitalize()) # fire_3, piston_head_7...: their kind
	return Items.display_name(item)


static var _fast_graphics := false


## Fast graphics: blocks with a fast tile (leaves) become opaque with that
## tile, Fancy: back to cutout. Returns true if anything changed (re-mesh).
## The tables that change with Fast graphics, as they are with it (the
## native mesher's far chunks: opaque leaves, ChunkMesher.prepare_native).
static func fast_tables() -> Dictionary:
	var opaque := is_opaque_table.duplicate()
	var layers := layer_table.duplicate()
	var tiles := face_tiles.duplicate()
	for block in types:
		if block.fast_tile < 0:
			continue
		opaque[block.id] = 1
		layers[block.id] = Layer.OPAQUE
		for face in BlockType.FACE_COUNT:
			tiles[block.id * BlockType.FACE_COUNT + face] = block.fast_tile
	return {"is_opaque": opaque, "layer": layers, "face_tiles": tiles}


## 1 for blocks that look different with Fast graphics (leaves).
static func fast_leaves_table() -> PackedByteArray:
	if _fast_leaves.size() != types.size():
		_fast_leaves.resize(types.size())
		for block in types:
			_fast_leaves[block.id] = 1 if block.fast_tile >= 0 else 0
	return _fast_leaves


static var _fast_leaves := PackedByteArray()


static func is_fast_graphics() -> bool:
	return _fast_graphics


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
