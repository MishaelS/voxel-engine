class_name Stats
extends RefCounted
## Statistics and achievements like Beta 1.7.3, kept for the player across
## all worlds (user://stats.cfg), like the game's account stats.
## - Counters: general ones (time played, distances walked, swum, fallen,
##   climbed, flown and ridden, jumps, deaths, damage, kills, fish caught,
##   items dropped, games...) and per block / item ("mine.<block>",
##   "craft.<item>", "use.<item>", "break.<item>");
## - Achievements: the Beta ones that exist here (no Nether yet), each
##   needing its parent first; getting one shows a toast (AchievementToast)
##   and is saved at once.

const PATH := "user://stats.cfg"

## id -> [name, description, parent id, icon (item or block name), column, row]
const ACHIEVEMENTS := {
	"openInventory": ["Taking Inventory", "Press E to open your inventory.", "", "book", 0, 0],
	"mineWood": ["Getting Wood", "Attack a tree until a block of wood pops out", "openInventory", "oak_log", 2, 1],
	"buildWorkBench": ["Benchmarking", "Craft a workbench with four blocks of planks", "mineWood", "crafting_table", 4, -1],
	"buildPickaxe": ["Time to Mine!", "Use planks and sticks to make a pickaxe", "buildWorkBench", "wooden_pickaxe", 4, 2],
	"buildFurnace": ["Hot Topic", "Construct a furnace out of eight cobblestone blocks", "buildPickaxe", "furnace", 3, 4],
	"acquireIron": ["Acquire Hardware", "Smelt an iron ingot", "buildFurnace", "iron_ingot", 1, 4],
	"buildHoe": ["Time to Farm!", "Use planks and sticks to make a hoe", "buildWorkBench", "wooden_hoe", 2, -3],
	"makeBread": ["Bake Bread", "Turn wheat into bread", "buildHoe", "bread", -1, -3],
	"bakeCake": ["The Lie", "Wheat, sugar, milk and eggs!", "buildHoe", "cake", 0, -5],
	"buildBetterPickaxe": ["Getting an Upgrade", "Construct a better pickaxe", "buildPickaxe", "stone_pickaxe", 6, 2],
	"cookFish": ["Delicious Fish", "Catch and cook fish!", "buildFurnace", "cooked_fish", 2, 6],
	"onARail": ["On A Rail", "Travel by minecart at least 1 km from where you started", "acquireIron", "rail", 2, 3],
	"buildSword": ["Time to Strike!", "Use planks and sticks to make a sword", "buildWorkBench", "wooden_sword", 6, -1],
	"killEnemy": ["Monster Hunter", "Attack and destroy a monster", "buildSword", "bone", 8, -1],
	"killCow": ["Cow Tipper", "Harvest some leather", "buildSword", "leather", 7, -3],
	"flyPig": ["When Pigs Fly", "Fly a pig off a cliff", "killCow", "saddle", 8, -4],
	"snipeSkeleton": ["Sniper Duel", "Kill a skeleton with an arrow from more than 50 meters", "killEnemy", "bow", 7, 0],
	"diamonds": ["DIAMONDS!", "Acquire diamonds with your iron tools", "acquireIron", "diamond", -1, 5],
}
## General counters in the statistics window: key -> [name, kind]
## (kind: "count", "time" in ticks, "distance" in centimeters).
const GENERAL := [
	["games_played", "Games Played", "count"],
	["saves_loaded", "Saves Loaded", "count"],
	["worlds_created", "Worlds Created", "count"],
	["leave_game", "Games Quit", "count"],
	["play_ticks", "Minutes Played", "time"],
	["walk_cm", "Distance Walked", "distance"],
	["swim_cm", "Distance Swum", "distance"],
	["fall_cm", "Distance Fallen", "distance"],
	["climb_cm", "Distance Climbed", "distance"],
	["fly_cm", "Distance Flown", "distance"],
	["minecart_cm", "Distance by Minecart", "distance"],
	["boat_cm", "Distance by Boat", "distance"],
	["pig_cm", "Distance by Pig", "distance"],
	["jumps", "Jumps", "count"],
	["drops", "Items Dropped", "count"],
	["damage_dealt", "Damage Dealt", "count"],
	["damage_taken", "Damage Taken", "count"],
	["deaths", "Number of Deaths", "count"],
	["mob_kills", "Mob Kills", "count"],
	["fish_caught", "Fish Caught", "count"],
]

static var _counters := {}
static var _unlocked := {}
static var _loaded := false
static var _dirty := false
## Called with an achievement id when one is gotten (the toast listens).
static var on_achievement := Callable()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key in file.get_section_keys("stats") if file.has_section("stats") else PackedStringArray():
		_counters[key] = int(file.get_value("stats", key, 0))
	for key in file.get_section_keys("achievements") if file.has_section("achievements") else PackedStringArray():
		_unlocked[key] = true


static func save() -> void:
	if not _loaded or not _dirty:
		return
	_dirty = false
	var file := ConfigFile.new()
	for key: String in _counters:
		file.set_value("stats", key, _counters[key])
	for key: String in _unlocked:
		file.set_value("achievements", key, true)
	file.save(PATH)


static func add(key: String, amount: int = 1) -> void:
	if amount == 0:
		return
	_load()
	_counters[key] = int(_counters.get(key, 0)) + amount
	_dirty = true


static func value(key: String) -> int:
	_load()
	return int(_counters.get(key, 0))


## All counters starting with `prefix` ("mine.", "craft."...): name -> count.
static func with_prefix(prefix: String) -> Dictionary:
	_load()
	var result := {}
	for key: String in _counters:
		if key.begins_with(prefix):
			result[key.trim_prefix(prefix)] = _counters[key]
	return result


static func has(id: String) -> bool:
	_load()
	return _unlocked.has(id)


## Whether the achievement can be gotten now (its parent is done).
static func can_get(id: String) -> bool:
	var parent: String = ACHIEVEMENTS[id][2]
	return parent == "" or has(parent)


## Gets an achievement (if its parent is done and it isn't yet).
static func grant(id: String) -> void:
	_load()
	if not ACHIEVEMENTS.has(id) or _unlocked.has(id) or not can_get(id):
		return
	_unlocked[id] = true
	_dirty = true
	save()
	if on_achievement.is_valid():
		on_achievement.call(id)


# --- What triggers them ---------------------------------------------------------------

## An item went into the inventory (picked up).
static func picked_up(id: int) -> void:
	var name := Items.name_of(id)
	if name.ends_with("_log"):
		grant("mineWood")
	elif name == "leather":
		grant("killCow")
	elif name == "diamond":
		grant("diamonds")


## Something was crafted (count of it).
static func crafted(id: int, count: int) -> void:
	var name := Items.name_of(id)
	add("craft." + name, count)
	if name == "crafting_table":
		grant("buildWorkBench")
	elif name.ends_with("_pickaxe"):
		grant("buildPickaxe")
		if name != "wooden_pickaxe":
			grant("buildBetterPickaxe")
	elif name == "furnace":
		grant("buildFurnace")
	elif name.ends_with("_hoe"):
		grant("buildHoe")
	elif name == "bread":
		grant("makeBread")
	elif name == "cake":
		grant("bakeCake")
	elif name.ends_with("_sword"):
		grant("buildSword")


## Something taken out of a furnace.
static func smelted(id: int, count: int) -> void:
	var name := Items.name_of(id)
	add("craft." + name, count)
	if name == "iron_ingot":
		grant("acquireIron")
	elif name == "cooked_fish":
		grant("cookFish")


## A creature was killed by the player (`by_arrow_from`: the shooter's place
## for arrows, else null).
static func killed(mob: Entity, by_arrow_from: Variant = null) -> void:
	add("mob_kills")
	if mob is Mob and (mob as Mob).is_hostile():
		grant("killEnemy")
		if (mob as Mob).mob_type == "skeleton" and by_arrow_from is Vector3 \
				and (by_arrow_from as Vector3).distance_to(mob.feet()) > 50.0:
			grant("snipeSkeleton")


## Formats a counter like the game's statistics window.
static func format(key: String, kind: String) -> String:
	var amount := value(key)
	match kind:
		"time":
			return "%.1f" % (amount / 20.0 / 60.0)
		"distance":
			if amount >= 100000:
				return "%.2f km" % (amount / 100000.0)
			if amount >= 100:
				return "%.1f m" % (amount / 100.0)
			return "%d cm" % amount
	return str(amount)
