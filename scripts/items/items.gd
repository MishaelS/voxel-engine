class_name Items
extends RefCounted
## Every item id: blocks are items with their block id (below FIRST_ITEM),
## other items (ItemType) come from FIRST_ITEM on. Ids are given in
## registration order: always append at the end (saved inventories depend
## on them).

const FIRST_ITEM := 32768
## Where items started in saves before block ids went past 256.
const OLD_FIRST_ITEM := 256
const ICONS_PATH := "res://assets/textures/items.png"
const MAX_STACK := 64

## Tool materials like the classic game: [name, tier, speed, uses, icon column].
const TOOL_MATERIALS := [
	["wooden", 0, 2.0, 59, 0], ["stone", 1, 4.0, 131, 1], ["iron", 2, 6.0, 250, 2],
	["diamond", 3, 8.0, 1561, 3], ["golden", 0, 12.0, 32, 4],
]
## Tool kinds and the items.png row of their icons.
const TOOL_KINDS := [["sword", 4], ["shovel", 5], ["pickaxe", 6], ["axe", 7]]

## Block fuel in ticks (items keep theirs in ItemType.fuel).
const BLOCK_FUEL := {
	"oak_planks": 300, "birch_planks": 300, "spruce_planks": 300,
	"oak_log": 300, "birch_log": 300, "spruce_log": 300,
	"crafting_table": 300, "chest": 300,
}

static var types: Array[ItemType] = []
static var _ids_by_name := {}
static var _icons := {} # id -> AtlasTexture
static var _registered := _register_all()


static func _register_all() -> bool:
	register(ItemType.make("stick", 53).set_fuel(100))
	register(ItemType.make("coal", 7).set_fuel(1600))
	register(ItemType.make("charcoal", 7).set_fuel(1600))
	register(ItemType.make("iron_ingot", 23))
	register(ItemType.make("gold_ingot", 39))
	register(ItemType.make("diamond", 55))
	register(ItemType.make("redstone", 56))
	register(ItemType.make("flint", 6))
	register(ItemType.make("snowball", 14).stack(16))
	register(ItemType.make("apple", 10).set_food(4, 0.3, 4))
	register(ItemType.make("bucket", 74).stack(16))
	register(ItemType.make("water_bucket", 75).stack(1))
	register(ItemType.make("bed", 45).stack(1))
	for material: Array in TOOL_MATERIALS:
		for kind: Array in TOOL_KINDS:
			var tool := ItemType.make("%s_%s" % [material[0], kind[0]], kind[1] * 16 + material[4]) \
				.set_tool(kind[0], material[1], material[2], material[3])
			if material[0] == "wooden":
				tool.set_fuel(200)
			register(tool)
	# Appended: ids stay stable.
	register(ItemType.make("seeds", 9).set_places("wheat_crop"))
	register(ItemType.make("lava_bucket", 76).stack(1).set_fuel(20000))
	register(ItemType.make("glowstone_dust", 73))
	register(ItemType.make("flint_and_steel", 5).set_durability(64))
	register(ItemType.make("clay_ball", 57))
	register(ItemType.make("brick", 22))
	register(ItemType.make("paper", 58))
	register(ItemType.make("book", 59))
	register(ItemType.make("string", 8))
	register(ItemType.make("wooden_door", 43).stack(1))
	register(ItemType.make("iron_door", 44).stack(1))
	register(ItemType.make("sign", 42).stack(1))
	register(ItemType.make("sugar_cane", 27).set_places("sugar_cane_block"))
	register(ItemType.make("sugar", 13))
	register(ItemType.make("bowl", 71))
	register(ItemType.make("mushroom_stew", 72).stack(1).set_food(6, 0.6, 10).set_container("bowl"))
	register(ItemType.make("cactus_green", 110))
	for material: Array in TOOL_MATERIALS:
		register(ItemType.make(material[0] + "_hoe", 128 + material[4]).set_tool("hoe", material[1], 1.0, material[3]))
	register(ItemType.make("wheat", 25))
	register(ItemType.make("bread", 41).set_food(5, 0.6, 5))
	register(ItemType.make("bone", 28))
	register(ItemType.make("bone_meal", 191))
	register(ItemType.make("cake", 29).stack(1).set_places("cake"))
	register(ItemType.make("cookie", 92).set_food(2, 0.1, 1))
	register(ItemType.make("cocoa_beans", 126))
	register(ItemType.make("golden_apple", 11).set_food(4, 1.2, 20))
	register(ItemType.make("milk_bucket", 77).stack(1).set_container("bucket"))
	register(ItemType.make("egg", 12).stack(16))
	register(ItemType.make("porkchop", 87).set_food(3, 0.3, 3))
	register(ItemType.make("cooked_porkchop", 88).set_food(8, 0.8, 8))
	register(ItemType.make("leather", 103))
	register(ItemType.make("feather", 24))
	register(ItemType.make("gunpowder", 40))
	register(ItemType.make("slimeball", 30))
	register(ItemType.make("ink_sac", 78))
	register(ItemType.make("saddle", 104).stack(1))
	register(ItemType.make("arrow", 37))
	register(ItemType.make("bow", 21).set_durability(384))
	register(ItemType.make("shears", 93).set_durability(238))
	register(ItemType.make("music_disc_13", 240).stack(1))
	register(ItemType.make("music_disc_cat", 241).stack(1))
	register(ItemType.make("raw_fish", 89).set_food(2, 0.1, 2))
	register(ItemType.make("cooked_fish", 90).set_food(5, 0.6, 5))
	_register_armor()
	return true


## Armor like Beta 1.7.3: every material gives the same points (helmet 3,
## chestplate 8, leggings 6, boots 3; 20 = the whole bar), the material
## only sets how long it lasts: [11, 16, 15, 13] x (leather 3, chain and
## gold 6, iron 12, diamond 24) hits.
const ARMOR_PIECES: Array[String] = ["helmet", "chestplate", "leggings", "boots"]
const ARMOR_POINTS: Array[int] = [3, 8, 6, 3]
const ARMOR_BASE: Array[int] = [11, 16, 15, 13]
## [material, durability factor, icon column].
const ARMOR_MATERIALS := [["leather", 3, 0], ["chainmail", 6, 1], ["iron", 12, 2], ["diamond", 24, 3], ["golden", 6, 4]]


static func _register_armor() -> void:
	for material: Array in ARMOR_MATERIALS:
		for slot in 4:
			register(ItemType.make("%s_%s" % [material[0], ARMOR_PIECES[slot]], slot * 16 + material[2])
				.set_armor(slot, ARMOR_POINTS[slot], material[0], ARMOR_BASE[slot] * material[1]))


static func register(item: ItemType) -> int:
	assert(not _ids_by_name.has(item.name), "Duplicate item name: " + item.name)
	item.id = FIRST_ITEM + types.size()
	types.append(item)
	_ids_by_name[item.name] = item.id
	return item.id


## An id from a save: saves without `item_base` numbered items from 256.
static func from_save(id: int, saved_base: int) -> int:
	if saved_base == FIRST_ITEM or id < saved_base:
		return id
	return id - saved_base + FIRST_ITEM


static func is_block(id: int) -> bool:
	return id < FIRST_ITEM


## The id of a block or item by its registry name.
static func id_of(item_name: String) -> int:
	if _ids_by_name.has(item_name):
		return _ids_by_name[item_name]
	return Blocks.id_of(item_name)


static func has_name(item_name: String) -> bool:
	return _ids_by_name.has(item_name) or Blocks._ids_by_name.has(item_name)


## True for ids a saved inventory may hold.
static func exists(id: int) -> bool:
	if id < FIRST_ITEM:
		return id > Blocks.AIR and id < Blocks.count()
	return id - FIRST_ITEM < types.size()


## The item type of a non-block item, or null for blocks.
static func get_type(id: int) -> ItemType:
	if id < FIRST_ITEM or id - FIRST_ITEM >= types.size():
		return null
	return types[id - FIRST_ITEM]


static func name_of(id: int) -> String:
	var item := get_type(id)
	return item.name if item else Blocks.get_type(id).name


static func max_stack(id: int) -> int:
	var item := get_type(id)
	return item.max_stack if item else MAX_STACK


static func durability(id: int) -> int:
	var item := get_type(id)
	return item.durability if item else 0


static func fuel_ticks(id: int) -> int:
	var item := get_type(id)
	if item:
		return item.fuel
	return BLOCK_FUEL.get(Blocks.get_type(id).name, 0) if id > Blocks.AIR else 0


## Display name ("iron_ingot" -> "Iron Ingot"), translated.
static func display_name(id: int) -> String:
	return Lang.t(name_of(id).capitalize())


## Icon of a non-block item (a tile of items.png).
static func icon(id: int) -> Texture2D:
	var item := get_type(id)
	if item == null:
		return null
	if not _icons.has(id):
		var texture := AtlasTexture.new()
		texture.atlas = load(ICONS_PATH)
		texture.region = Rect2((item.icon % 16) * 16, (item.icon / 16) * 16, 16, 16)
		_icons[id] = texture
	return _icons[id]


## Everything in the creative catalog: blocks first, then items.
static func catalog() -> PackedInt32Array:
	var result := PackedInt32Array()
	for block in Blocks.types:
		if block.id != Blocks.AIR and block.in_catalog:
			result.append(block.id)
	for item in types:
		result.append(item.id)
	return result


## Breaking speed of the item in hand on a block, like the classic game:
## the tool's speed if it is the right tool for the block, else 1.
static func break_speed(item_id: int, block_id: int) -> float:
	var item := get_type(item_id)
	var block := Blocks.get_type(block_id)
	if item == null or item.tool == "":
		return 1.0
	if item.tool == block.tool:
		return item.efficiency
	if item.tool == "sword" and block.name.ends_with("_leaves"):
		return 1.5
	if item.tool == "sword" and block.name == "cobweb":
		return 15.0
	if item.name == "shears":
		if block.name == "cobweb" or block.name.ends_with("_leaves"):
			return 15.0
		if block.name.ends_with("_wool"):
			return 5.0
	return 1.0


## Melee damage of the item in hand, like Beta 1.7.3: fist 1, swords
## 4 + 2 x tier (gold like wood), shovels 1 + tier, pickaxes 2 + tier,
## axes 3 + tier.
static func attack_damage(item_id: int) -> int:
	var item := get_type(item_id)
	if item == null:
		return 1
	match item.tool:
		"sword":
			return 4 + item.tier * 2
		"shovel":
			return 1 + item.tier
		"pickaxe":
			return 2 + item.tier
		"axe":
			return 3 + item.tier
	return 1


## Whether breaking the block with this item gives its drops.
static func can_harvest(item_id: int, block_id: int) -> bool:
	var block := Blocks.get_type(block_id)
	if block.harvest_level < 0:
		return true
	var item := get_type(item_id)
	return item != null and item.tool == block.tool and item.tier >= block.harvest_level
