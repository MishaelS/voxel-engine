class_name Smelting
extends RefCounted
## Furnace recipes like the classic game: what an item becomes after
## COOK_TICKS in a burning furnace. Fuel times are in Items.fuel_ticks().

const COOK_TICKS := 200

const RECIPES := {
	"cobblestone": "stone", "sand": "glass",
	"oak_log": "charcoal", "birch_log": "charcoal", "spruce_log": "charcoal",
	"iron_ore": "iron_ingot", "gold_ore": "gold_ingot", "diamond_ore": "diamond",
	"coal_ore": "coal", "redstone_ore": "redstone", "clay_ball": "brick", "cactus": "cactus_green",
	"porkchop": "cooked_porkchop", "raw_fish": "cooked_fish",
}


## What `id` smelts into, or AIR.
static func result_of(id: int) -> int:
	if id == Blocks.AIR:
		return Blocks.AIR
	var result: String = RECIPES.get(Items.name_of(id), "")
	return Items.id_of(result) if result != "" else Blocks.AIR
