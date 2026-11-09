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
## Food points and saturation modifier (0 = not food), like the classic game.
var food := 0
var saturation := 0.0
## Ticks it burns in a furnace (0 = not fuel).
var fuel := 0


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


func set_food(points: int, saturation_modifier: float) -> ItemType:
	food = points
	saturation = saturation_modifier
	return self


func set_fuel(ticks: int) -> ItemType:
	fuel = ticks
	return self
