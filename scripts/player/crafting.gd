class_name Crafting
extends RefCounted
## Shaped crafting recipes like the classic game: a pattern of up to 3x3
## items anywhere in the crafting grid (or mirrored left-right) gives a
## result. The inventory has a 2x2 grid, the crafting table a 3x3 one.
##
## To add a recipe, append to RECIPES: pattern rows (one character per
## cell, " " = empty), what each character means (an item name or an array
## of item names that are all accepted), the result and its count.
## A "$" result means "the same kind as the ingredient" (oak log -> oak
## planks) via the result_by_ingredient table.
## Shapeless recipes ({"shapeless": [item names], ...}) take their items
## anywhere in the grid (dyes, dyed wool).

const PLANKS := ["oak_planks", "birch_planks", "spruce_planks"]
const WOOL := [
	"white_wool", "orange_wool", "magenta_wool", "light_blue_wool", "yellow_wool", "lime_wool",
	"pink_wool", "gray_wool", "light_gray_wool", "cyan_wool", "purple_wool", "blue_wool",
	"brown_wool", "green_wool", "red_wool", "black_wool",
]
## Tool heads: material key -> what it is made of.
const TOOL_MATERIALS := {
	"wooden": PLANKS, "stone": "cobblestone", "iron": "iron_ingot",
	"diamond": "diamond", "golden": "gold_ingot",
}
## Armor: material key -> what it is made of (chainmail can't be crafted).
const ARMOR_MATERIALS := {"leather": "leather", "iron": "iron_ingot", "diamond": "diamond", "golden": "gold_ingot"}
const ARMOR_PATTERNS := {
	"helmet": ["MMM", "M M"],
	"chestplate": ["M M", "MMM", "MMM"],
	"leggings": ["MMM", "M M", "M M"],
	"boots": ["M M", "M M"],
}
const TOOL_PATTERNS := {
	"pickaxe": ["MMM", " S ", " S "],
	"axe": ["MM", "MS", " S"],
	"shovel": ["M", "S", "S"],
	"hoe": ["MM", " S", " S"],
	"sword": ["M", "M", "S"],
}

static var RECIPES: Array = _build_recipes()


static func _build_recipes() -> Array:
	var recipes := [
		{"pattern": ["L"], "keys": {"L": ["oak_log", "birch_log", "spruce_log"]},
			"result": "$", "count": 4,
			"result_by_ingredient": {"oak_log": "oak_planks", "birch_log": "birch_planks", "spruce_log": "spruce_planks"}},
		{"pattern": ["P", "P"], "keys": {"P": PLANKS}, "result": "stick", "count": 4},
		{"pattern": ["PP", "PP"], "keys": {"P": PLANKS}, "result": "crafting_table", "count": 1},
		{"pattern": ["PPP", "P P", "PPP"], "keys": {"P": PLANKS}, "result": "chest", "count": 1},
		{"pattern": ["CCC", "C C", "CCC"], "keys": {"C": "cobblestone"}, "result": "furnace", "count": 1},
		{"pattern": ["WWW", "PPP"], "keys": {"W": WOOL, "P": PLANKS}, "result": "bed", "count": 1},
		{"pattern": ["I I", " I "], "keys": {"I": "iron_ingot"}, "result": "bucket", "count": 1},
		{"pattern": ["SS", "SS"], "keys": {"S": "sand"}, "result": "sandstone", "count": 1},
		{"pattern": ["SS", "SS"], "keys": {"S": "snowball"}, "result": "snow", "count": 1},
		{"pattern": ["C", "S"], "keys": {"C": ["coal", "charcoal"], "S": "stick"}, "result": "torch", "count": 4},
		{"pattern": ["GG", "GG"], "keys": {"G": "glowstone_dust"}, "result": "glowstone", "count": 1},
		{"pattern": ["P", "T"], "keys": {"P": "carved_pumpkin", "T": "torch"}, "result": "jack_o_lantern", "count": 1},
		# Shears carve a face into a pumpkin (they stay, a little worn).
		{"shapeless": ["pumpkin", "shears"], "result": "carved_pumpkin", "count": 1},
		{"pattern": ["I ", " F"], "keys": {"I": "iron_ingot", "F": "flint"}, "result": "flint_and_steel", "count": 1},
		{"pattern": ["X  ", "XX ", "XXX"], "keys": {"X": "cobblestone"}, "result": "cobblestone_stairs", "count": 4},
		{"pattern": ["X  ", "XX ", "XXX"], "keys": {"X": "oak_planks"}, "result": "oak_stairs", "count": 4},
		{"pattern": ["X  ", "XX ", "XXX"], "keys": {"X": "birch_planks"}, "result": "birch_stairs", "count": 4},
		{"pattern": ["X  ", "XX ", "XXX"], "keys": {"X": "spruce_planks"}, "result": "spruce_stairs", "count": 4},
		{"pattern": ["XXX"], "keys": {"X": "stone"}, "result": "stone_slab", "count": 3},
		{"pattern": ["XXX"], "keys": {"X": "sandstone"}, "result": "sandstone_slab", "count": 3},
		{"pattern": ["XXX"], "keys": {"X": PLANKS}, "result": "wooden_slab", "count": 3},
		{"pattern": ["XXX"], "keys": {"X": "cobblestone"}, "result": "cobblestone_slab", "count": 3},
		{"pattern": ["SSS", "SSS"], "keys": {"S": "stick"}, "result": "fence", "count": 2},
		{"pattern": ["S S", "SSS", "S S"], "keys": {"S": "stick"}, "result": "ladder", "count": 2},
		{"pattern": ["PP", "PP", "PP"], "keys": {"P": PLANKS}, "result": "wooden_door", "count": 1},
		{"pattern": ["II", "II", "II"], "keys": {"I": "iron_ingot"}, "result": "iron_door", "count": 1},
		{"pattern": ["PPP", "PPP"], "keys": {"P": PLANKS}, "result": "trapdoor", "count": 2},
		{"pattern": ["PPP", "PPP", " S "], "keys": {"P": PLANKS, "S": "stick"}, "result": "sign", "count": 1},
		{"pattern": ["BB", "BB"], "keys": {"B": "brick"}, "result": "bricks", "count": 1},
		{"pattern": ["CC", "CC"], "keys": {"C": "clay_ball"}, "result": "clay", "count": 1},
		{"pattern": ["P", "P", "P"], "keys": {"P": "paper"}, "result": "book", "count": 1},
		{"pattern": ["S"], "keys": {"S": "sugar_cane"}, "result": "sugar", "count": 1},
		{"pattern": ["WWW"], "keys": {"W": "wheat"}, "result": "bread", "count": 1},
		{"pattern": [" SW", "S W", " SW"], "keys": {"S": "stick", "W": "string"}, "result": "bow", "count": 1},
		{"pattern": ["F", "S", "E"], "keys": {"F": "flint", "S": "stick", "E": "feather"}, "result": "arrow", "count": 4},
		{"pattern": [" I", "I "], "keys": {"I": "iron_ingot"}, "result": "shears", "count": 1},
		{"pattern": ["B"], "keys": {"B": "bone"}, "result": "bone_meal", "count": 3},
		{"pattern": [" I ", "IRI", " I "], "keys": {"I": "iron_ingot", "R": "redstone"}, "result": "compass", "count": 1},
		{"pattern": ["PPP", "PRP", "PPP"], "keys": {"P": PLANKS, "R": "redstone"}, "result": "note_block", "count": 1},
		{"pattern": ["GSG", "SGS", "GSG"], "keys": {"G": "gunpowder", "S": "sand"}, "result": "tnt", "count": 1},
		{"pattern": ["R", "S"], "keys": {"R": "redstone", "S": "stick"}, "result": "redstone_torch", "count": 1},
		{"pattern": ["I I", "ISI", "I I"], "keys": {"I": "iron_ingot", "S": "stick"}, "result": "rail", "count": 16},
		{"pattern": ["G G", "GSG", "GRG"], "keys": {"G": "gold_ingot", "S": "stick", "R": "redstone"}, "result": "powered_rail", "count": 6},
		{"pattern": ["I I", "IPI", "IRI"], "keys": {"I": "iron_ingot", "P": "stone_pressure_plate", "R": "redstone"}, "result": "detector_rail", "count": 6},
		{"pattern": ["I I", "III"], "keys": {"I": "iron_ingot"}, "result": "minecart", "count": 1},
		{"pattern": ["C", "M"], "keys": {"C": "chest", "M": "minecart"}, "result": "chest_minecart", "count": 1},
		{"pattern": ["F", "M"], "keys": {"F": "furnace", "M": "minecart"}, "result": "furnace_minecart", "count": 1},
		{"pattern": ["P P", "PPP"], "keys": {"P": PLANKS}, "result": "boat", "count": 1},
		{"pattern": ["TRT", "SSS"], "keys": {"T": "redstone_torch", "R": "redstone", "S": "stone"}, "result": "repeater", "count": 1},
		{"pattern": ["S", "C"], "keys": {"S": "stick", "C": "cobblestone"}, "result": "lever", "count": 1},
		{"pattern": ["S", "S"], "keys": {"S": "stone"}, "result": "stone_button", "count": 1},
		{"pattern": ["SS"], "keys": {"S": "stone"}, "result": "stone_pressure_plate", "count": 1},
		{"pattern": ["PP"], "keys": {"P": PLANKS}, "result": "wooden_pressure_plate", "count": 1},
		{"pattern": ["PPP", "CIC", "CRC"], "keys": {"P": PLANKS, "C": "cobblestone", "I": "iron_ingot", "R": "redstone"}, "result": "piston", "count": 1},
		{"pattern": ["S", "P"], "keys": {"S": "slimeball", "P": "piston"}, "result": "sticky_piston", "count": 1},
		{"pattern": ["CCC", "CBC", "CRC"], "keys": {"C": "cobblestone", "B": "bow", "R": "redstone"}, "result": "dispenser", "count": 1},
		{"pattern": ["PPP", "PDP", "PPP"], "keys": {"P": PLANKS, "D": "diamond"}, "result": "jukebox", "count": 1},
		{"pattern": ["SSS", "SWS", "SSS"], "keys": {"S": "stick", "W": WOOL}, "result": "painting", "count": 1},
		{"pattern": ["  S", " SW", "S W"], "keys": {"S": "stick", "W": "string"}, "result": "fishing_rod", "count": 1},
		{"pattern": ["PPP", "PCP", "PPP"], "keys": {"P": "paper", "C": "compass"}, "result": "map", "count": 1},
		{"pattern": [" G ", "GRG", " G "], "keys": {"G": "gold_ingot", "R": "redstone"}, "result": "clock", "count": 1},
		{"pattern": ["MMM", "SES", "WWW"], "keys": {"M": "milk_bucket", "S": "sugar", "E": "egg", "W": "wheat"}, "result": "cake", "count": 1},
		{"pattern": ["WCW"], "keys": {"W": "wheat", "C": "cocoa_beans"}, "result": "cookie", "count": 8},
		{"pattern": ["GGG", "GAG", "GGG"], "keys": {"G": "gold_block", "A": "apple"}, "result": "golden_apple", "count": 1},
		{"pattern": ["SSS"], "keys": {"S": "sugar_cane"}, "result": "paper", "count": 3},
		{"pattern": ["P P", " P "], "keys": {"P": PLANKS}, "result": "bowl", "count": 4},
		{"pattern": ["B", "R", "W"], "keys": {"B": "brown_mushroom", "R": "red_mushroom", "W": "bowl"}, "result": "mushroom_stew", "count": 1},
		{"pattern": ["R", "B", "W"], "keys": {"B": "brown_mushroom", "R": "red_mushroom", "W": "bowl"}, "result": "mushroom_stew", "count": 1},
		{"pattern": ["PPP", "BBB", "PPP"], "keys": {"P": PLANKS, "B": "book"}, "result": "bookshelf", "count": 1},
	]
	for block: String in ["iron", "gold", "diamond"]:
		var item := "diamond" if block == "diamond" else block + "_ingot"
		recipes.append({"pattern": ["XXX", "XXX", "XXX"], "keys": {"X": item}, "result": block + "_block", "count": 1})
		recipes.append({"pattern": ["B"], "keys": {"B": block + "_block"}, "result": item, "count": 9})
	for material: String in TOOL_MATERIALS:
		for kind: String in TOOL_PATTERNS:
			recipes.append({"pattern": TOOL_PATTERNS[kind], "keys": {"M": TOOL_MATERIALS[material], "S": "stick"},
				"result": "%s_%s" % [material, kind], "count": 1})
	recipes.append_array(_dye_recipes())
	for material: String in ARMOR_MATERIALS:
		for piece: String in ARMOR_PATTERNS:
			recipes.append({"pattern": ARMOR_PATTERNS[piece], "keys": {"M": ARMOR_MATERIALS[material]},
				"result": "%s_%s" % [material, piece], "count": 1})
	return recipes


## Dyes like the classic game: from flowers and lapis, mixed into the
## other colors, and dyeing white wool.
static func _dye_recipes() -> Array:
	var recipes := [
		{"shapeless": ["rose"], "result": "rose_red", "count": 2},
		{"shapeless": ["dandelion"], "result": "dandelion_yellow", "count": 2},
		{"pattern": ["LLL", "LLL", "LLL"], "keys": {"L": "lapis_lazuli"}, "result": "lapis_block", "count": 1},
		{"pattern": ["B"], "keys": {"B": "lapis_block"}, "result": "lapis_lazuli", "count": 9},
		{"shapeless": ["rose_red", "dandelion_yellow"], "result": "orange_dye", "count": 2},
		{"shapeless": ["lapis_lazuli", "rose_red"], "result": "purple_dye", "count": 2},
		{"shapeless": ["lapis_lazuli", "cactus_green"], "result": "cyan_dye", "count": 2},
		{"shapeless": ["gray_dye", "bone_meal"], "result": "light_gray_dye", "count": 2},
		{"shapeless": ["ink_sac", "bone_meal", "bone_meal"], "result": "light_gray_dye", "count": 3},
		{"shapeless": ["ink_sac", "bone_meal"], "result": "gray_dye", "count": 2},
		{"shapeless": ["rose_red", "bone_meal"], "result": "pink_dye", "count": 2},
		{"shapeless": ["cactus_green", "bone_meal"], "result": "lime_dye", "count": 2},
		{"shapeless": ["lapis_lazuli", "bone_meal"], "result": "light_blue_dye", "count": 2},
		{"shapeless": ["purple_dye", "pink_dye"], "result": "magenta_dye", "count": 2},
		{"shapeless": ["lapis_lazuli", "rose_red", "pink_dye"], "result": "magenta_dye", "count": 3},
		{"shapeless": ["lapis_lazuli", "rose_red", "rose_red", "bone_meal"], "result": "magenta_dye", "count": 4},
	]
	for dye: String in Items.DYE_COLORS:
		var color: String = Items.DYE_COLORS[dye]
		if color != "white":
			recipes.append({"shapeless": [dye, "white_wool"], "result": color + "_wool", "count": 1})
	return recipes


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
		if recipe.has("shapeless"):
			if _match_shapeless(recipe.shapeless, grid):
				return {"id": Items.id_of(recipe.result), "count": recipe.count}
			continue
		var pattern: Array = recipe.pattern
		if pattern.size() != max_y - min_y + 1 or (pattern[0] as String).length() != max_x - min_x + 1:
			continue
		for mirrored in [false, true]:
			var ingredient := _match(recipe, grid, width, min_x, min_y, mirrored)
			if ingredient >= 0:
				var result_name: String = recipe.result
				if result_name == "$":
					result_name = recipe.result_by_ingredient[Items.name_of(ingredient)]
				return {"id": Items.id_of(result_name), "count": recipe.count}
	return {}


## Whether the grid holds exactly these items (one each), anywhere.
static func _match_shapeless(names: Array, grid: PackedInt32Array) -> bool:
	var wanted := names.duplicate()
	for id in grid:
		if id == Blocks.AIR:
			continue
		var at := wanted.find(Items.name_of(id))
		if at < 0:
			return false
		wanted.remove_at(at)
	return wanted.is_empty()


## The (single) ingredient kind if the grid matches the recipe, else -1.
static func _match(recipe: Dictionary, grid: PackedInt32Array, width: int, min_x: int, min_y: int, mirrored: bool) -> int:
	var pattern: Array = recipe.pattern
	var ingredient := Blocks.AIR
	var kinds := {} # key -> item
	for y in pattern.size():
		var row: String = pattern[y]
		for x in row.length():
			var key := row[row.length() - 1 - x] if mirrored else row[x]
			var id := grid[(min_x + x) + (min_y + y) * width]
			if not _accepts(recipe.keys, key, id):
				return -1
			if id == Blocks.AIR:
				continue
			if kinds.has(key) and kinds[key] != id and key != "W":
				return -1 # one kind per ingredient (no mixed planks); wool colors may mix
			kinds[key] = id
			if ingredient == Blocks.AIR:
				ingredient = id
	return ingredient


static func _accepts(keys: Dictionary, key: String, id: int) -> bool:
	if key == " ":
		return id == Blocks.AIR
	if id == Blocks.AIR:
		return false
	var accepted: Variant = keys[key]
	var item_name := Items.name_of(id)
	if accepted is Array:
		return (accepted as Array).has(item_name)
	return accepted == item_name
