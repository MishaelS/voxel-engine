class_name ItemType
extends RefCounted
## An item that is not a block (tools, ingots, food, buckets, the bed),
## like the classic game's items. Drawn with its icon from items.png.

var id := 0
var name := ""
## Tile of items.png (16 x 16 tiles of 16 px, index = row * 16 + column).
var icon := 0
var max_stack := 64
## Tools: kind ("pickaxe", "shovel", "axe", "sword"), tier (0 wood / gold,
## 1 stone, 2 iron, 3 diamond), breaking speed on the right blocks and
## uses before it breaks.
var tool := ""
var tier := -1
var efficiency := 1.0
var durability := 0
## Food points and saturation modifier (0 = not food), like the classic game
## with hunger; `heal`: health it gives at once without hunger (Beta 1.7.3).
var food := 0
var saturation := 0.0
var heal := 0
## Ticks it burns in a furnace (0 = not fuel).
var fuel := 0
## The block this item places (sugar cane), "" = none.
var places := ""
## What is left after eating it (the bowl of a stew), "" = nothing.
var container := ""


static func make(item_name: String, icon_tile: int) -> ItemType:
	var item := ItemType.new()
	item.name = item_name
	item.icon = icon_tile
	return item


func stack(count: int) -> ItemType:
	max_stack = count
	return self


func set_tool(kind: String, tool_tier: int, speed: float, uses: int) -> ItemType:
	tool = kind
	tier = tool_tier
	efficiency = speed
	durability = uses
	max_stack = 1
	return self


## Uses before it breaks, for non-tools (flint and steel).
## Armor: the slot it is worn in (0 helmet, 1 chestplate, 2 leggings,
## 3 boots; -1 = not armor) and its armor points (half chestplate icons).
var armor_slot := -1
var armor := 0
var armor_material := ""


func set_armor(slot: int, points: int, material: String, uses: int) -> ItemType:
	armor_slot = slot
	armor = points
	armor_material = material
	max_stack = 1
	durability = uses
	return self


func set_durability(uses: int) -> ItemType:
	durability = uses
	max_stack = 1
	return self


func set_food(points: int, saturation_modifier: float, health: int = 0) -> ItemType:
	food = points
	saturation = saturation_modifier
	heal = health if health > 0 else points
	return self


func set_places(block_name: String) -> ItemType:
	places = block_name
	return self


func set_container(item_name: String) -> ItemType:
	container = item_name
	return self


func set_fuel(ticks: int) -> ItemType:
	fuel = ticks
	return self
