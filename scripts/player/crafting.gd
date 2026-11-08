class_name Crafting
extends RefCounted
## Shaped crafting recipes, like the classic game: a pattern of up to 3x3
## blocks anywhere in the crafting grid gives a result. The survival
## inventory has a 2x2 grid, so recipes that fit in 2x2 work there.
##
## To add a recipe, append to RECIPES: pattern rows (one character per
## cell, " " = empty), what each character means (a block name or an
## array of block names that are all accepted), the result and its count.
## A "$" result means "the same kind as the ingredient" (oak log -> oak
## planks) via the result_by_ingredient table.

const RECIPES := [
	{"pattern": ["L"], "keys": {"L": ["oak_log", "birch_log", "spruce_log"]},
		"result": "$", "count": 4,
		"result_by_ingredient": {"oak_log": "oak_planks", "birch_log": "birch_planks", "spruce_log": "spruce_planks"}},
	{"pattern": ["PP", "PP"], "keys": {"P": ["oak_planks", "birch_planks", "spruce_planks"]},
		"result": "crafting_table", "count": 1},
	{"pattern": ["SS", "SS"], "keys": {"S": "sand"}, "result": "sandstone", "count": 1},
	{"pattern": ["SS", "SS"], "keys": {"S": "snow"}, "result": "snow", "count": 1},
]


## Result of a crafting grid of `width` columns (ids row by row, AIR =
## empty): {"id": int, "count": int}, or {} if nothing matches.
static func result_of(grid: PackedInt32Array, width: int) -> Dictionary:
	var height := grid.size() / width
	# Bounding box of the filled cells.
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in height:
		for x in width:
			if grid[x + y * width] != Blocks.AIR:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return {}
	for recipe: Dictionary in RECIPES:
		var pattern: Array = recipe.pattern
		if pattern.size() != max_y - min_y + 1 or (pattern[0] as String).length() != max_x - min_x + 1:
			continue
		var ingredient := Blocks.AIR
		var matches := true
		for y in pattern.size():
			var row: String = pattern[y]
			for x in row.length():
				var id := grid[(min_x + x) + (min_y + y) * width]
				if not _accepts(recipe.keys, row[x], id):
					matches = false
					break
				if id != Blocks.AIR:
					if ingredient != Blocks.AIR and ingredient != id:
						matches = false # one kind per recipe (no mixed planks)
						break
					ingredient = id
			if not matches:
				break
		if matches:
			var result_name: String = recipe.result
			if result_name == "$":
				result_name = recipe.result_by_ingredient[Blocks.get_type(ingredient).name]
			return {"id": Blocks.id_of(result_name), "count": recipe.count}
	return {}


static func _accepts(keys: Dictionary, key: String, id: int) -> bool:
	if key == " ":
		return id == Blocks.AIR
	if id == Blocks.AIR:
		return false
	var accepted: Variant = keys[key]
	var block_name := Blocks.get_type(id).name
	if accepted is Array:
		return (accepted as Array).has(block_name)
	return accepted == block_name
