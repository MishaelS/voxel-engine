class_name EntitySelector
extends RefCounted
## A parsed target selector like the classic game's, chosen when the
## command runs (select()):
##   @p  the nearest player     @a  every player     @r  a random player
##   @s  the executor           @e  every entity     Name  that player
## Filters in brackets, separated by commas (no spaces):
##   type=pig / type=!player       name=Steve / name=!Steve
##   distance=10 / ..10 / 5.. / 2..8  (from the command's position)
##   x= y= z=  (the position to measure from)   dx= dy= dz=  (a box from x y z)
##   limit=3   sort=nearest|furthest|random|arbitrary
##   gamemode=survival|creative / !creative  (players)
## e.g. @e[type=zombie,distance=..16,limit=2,sort=nearest]

const KINDS: Array[String] = ["p", "a", "r", "s", "e"]
const KEYS: Array[String] = ["type", "name", "distance", "x", "y", "z", "dx", "dy", "dz", "limit", "sort", "gamemode"]
const SORTS: Array[String] = ["nearest", "furthest", "random", "arbitrary"]
const GAME_MODES: Array[String] = ["survival", "creative"]

## "p", "a", "r", "s", "e", or "" for a player's name.
var kind := ""
var player_name := ""
## [value, negated] pairs.
var types: Array = []
var names: Array = []
var game_modes: Array = []
var distance_min := -INF
var distance_max := INF
## The point to measure from (NAN: the command's position) and the box.
var at := Vector3(NAN, NAN, NAN)
var box := Vector3(NAN, NAN, NAN)
var limit := -1
var sort := ""


## Parses "@e[type=pig]" or a name. Returns the selector or an error String.
static func parse(text: String) -> Variant:
	var selector := EntitySelector.new()
	if not text.begins_with("@"):
		if text.is_empty() or text.is_valid_float() or text[0] in ["~", "^", "["] or text.contains("[") or text.contains("="):
			return Lang.t("Invalid name or selector '%s'") % text
		selector.player_name = text
		return selector
	var kind_text := text.substr(1, 1)
	if not kind_text in KINDS:
		return Lang.t("Unknown selector type '%s'") % text.left(2)
	selector.kind = kind_text
	var rest := text.substr(2)
	if rest.is_empty():
		return selector
	if not rest.begins_with("[") or not rest.ends_with("]"):
		return Lang.t("Expected [filters] after the selector, got '%s'") % rest
	var inner := rest.substr(1, rest.length() - 2)
	if inner.is_empty():
		return selector
	for pair in inner.split(","):
		var eq := pair.find("=")
		if eq <= 0:
			return Lang.t("Expected a filter, got '%s'") % pair
		var error := selector._set_filter(pair.left(eq), pair.substr(eq + 1))
		if error != "":
			return error
	return selector


func _set_filter(key: String, value: String) -> String:
	var negated := value.begins_with("!")
	var plain := value.substr(1) if negated else value
	match key:
		"type":
			if not plain in CommandTargets.type_names():
				return Lang.t("Unknown entity type '%s'") % plain
			types.append([plain, negated])
		"name":
			names.append([plain, negated])
		"gamemode":
			if not plain in GAME_MODES:
				return Lang.t("Unknown game mode '%s'") % plain
			game_modes.append([plain, negated])
		"distance":
			var range_value: Variant = _range(value)
			if range_value == null:
				return Lang.t("Invalid range '%s'") % value
			distance_min = range_value.x
			distance_max = range_value.y
		"x", "y", "z", "dx", "dy", "dz":
			if not value.is_valid_float():
				return Lang.t("Expected number, got '%s'") % value
			var axis := "xyz".find(key.right(1))
			if key.begins_with("d"):
				box[axis] = value.to_float()
			else:
				at[axis] = value.to_float()
		"limit":
			if not value.is_valid_int() or value.to_int() < 1:
				return Lang.t("Invalid limit '%s'") % value
			limit = value.to_int()
		"sort":
			if not value in SORTS:
				return Lang.t("Unknown sort '%s'") % value
			sort = value
		_:
			return Lang.t("Unknown option '%s'") % key
	return ""


## "5", "..5", "5..", "2..8" -> Vector2(min, max), or null.
static func _range(text: String) -> Variant:
	if text.is_valid_float():
		return Vector2(text.to_float(), text.to_float())
	var dots := text.find("..")
	if dots < 0:
		return null
	var low := text.left(dots)
	var high := text.substr(dots + 2)
	if (low != "" and not low.is_valid_float()) or (high != "" and not high.is_valid_float()) or (low == "" and high == ""):
		return null
	return Vector2(low.to_float() if low != "" else -INF, high.to_float() if high != "" else INF)


## Whether it can only ever give one target.
func is_single() -> bool:
	return limit == 1 or (kind in ["", "p", "r", "s"] and limit <= 1)


## Whether it can only give players.
func players_only() -> bool:
	if kind in ["", "p", "a", "r"]:
		return true
	if kind == "s":
		return true # (judged when it runs: commands skip what is not a player)
	for entry: Array in types:
		if entry[0] == "player" and not entry[1]:
			return true
	return false


## The targets for a command run by `source`.
func select(source: CommandSource) -> Array:
	var world := source.world
	var candidates := []
	match kind:
		"":
			for player: Variant in CommandTargets.players(world):
				if CommandTargets.name_of(player).to_lower() == player_name.to_lower():
					candidates.append(player)
		"s":
			if source.origin != null:
				candidates.append(source.origin)
		"e":
			candidates = CommandTargets.everything(world)
		_:
			candidates = CommandTargets.players(world)
			if kind == "p":
				candidates = candidates.filter(func(target: Variant) -> bool: return not bool(target.get("dead")))
	var origin := source.position()
	for axis in 3:
		if not is_nan(at[axis]):
			origin[axis] = at[axis]
	var result := candidates.filter(func(target: Variant) -> bool: return _matches(target, origin))
	var order := sort
	if order == "":
		order = {"p": "nearest", "r": "random"}.get(kind, "arbitrary")
	match order:
		"nearest", "furthest":
			var far := order == "furthest"
			result.sort_custom(func(a: Variant, b: Variant) -> bool:
				var da := CommandTargets.position_of(a).distance_squared_to(origin)
				var db := CommandTargets.position_of(b).distance_squared_to(origin)
				return da > db if far else da < db)
		"random":
			result.shuffle()
	var count := limit if limit > 0 else (1 if kind in ["p", "r"] else -1)
	if count > 0 and result.size() > count:
		result.resize(count)
	return result


func _matches(target: Variant, origin: Vector3) -> bool:
	var type := CommandTargets.type_of(target)
	for entry: Array in types:
		if (type == entry[0]) == entry[1]:
			return false
	var target_name := CommandTargets.name_of(target).to_lower()
	for entry: Array in names:
		if (target_name == (entry[0] as String).to_lower()) == entry[1]:
			return false
	if not game_modes.is_empty():
		if not target is Player:
			return false
		var mode := "creative" if (target as Player).is_creative() else "survival"
		for entry: Array in game_modes:
			if (mode == entry[0]) == entry[1]:
				return false
	var position := CommandTargets.position_of(target)
	if distance_min > -INF or distance_max < INF:
		var distance := position.distance_to(origin)
		if distance < distance_min or distance > distance_max:
			return false
	if not (is_nan(box.x) and is_nan(box.y) and is_nan(box.z)):
		var size := Vector3(0.0 if is_nan(box.x) else box.x, 0.0 if is_nan(box.y) else box.y, 0.0 if is_nan(box.z) else box.z)
		var area := AABB(origin, size).abs()
		area.size += Vector3.ONE # the classic game's boxes include the far blocks
		if not area.has_point(position):
			return false
	return true
