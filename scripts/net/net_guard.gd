class_name NetGuard
extends RefCounted
## What the host checks in what clients send (Net): text cleaned and cut
## short, names, positions, inventories and entity states made safe, and
## each client's movement kept to what the game allows (Mover).
##
## Nothing from the network is trusted: a changed client can send any
## value of the right type (Godot checks the argument types, not ranges),
## so every number is clamped or refused here before the world sees it.

## Names on a server: 3-16 of A-Z, a-z, 0-9 and _ (like the classic game).
const NAME_MIN := 3
const NAME_MAX := 16
const CHAT_MAX := 256
## A world coordinate further than this is refused (the classic world's
## edge is at 30 million).
const WORLD_LIMIT := 30000000.0
const Y_MIN := -128.0
const Y_MAX := 1024.0
## Bytes of a player's state a client may hand in for saving.
const PLAYER_STATE_BYTES := 32 * 1024
## Skins: a 64x64 PNG is a few KB.
const SKIN_BYTES := 24 * 1024

## BBCode tags the chat and labels would understand: taken out of what
## players write (the chat escapes "[" too; this keeps the logs clean).
static var _bbcode := RegEx.create_from_string(
	"\\[/?(b|i|u|s|code|p|center|left|right|fill|indent|url|img|font|font_size|size|color|bgcolor|fgcolor|" +
	"outline_size|outline_color|table|cell|ul|ol|lb|rb|wave|shake|rainbow|tornado|fade|pulse|hint|dropcap|" +
	"char|lang|opentype_features|br|hr)(=[^\\]]*)?( [^\\]]*)?\\]")
static var _name_pattern := RegEx.create_from_string("^[A-Za-z0-9_]{%d,%d}$" % [NAME_MIN, NAME_MAX])

const CYRILLIC := {
	"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i",
	"й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
	"у": "u", "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "",
	"э": "e", "ю": "yu", "я": "ya",
}


## Text from a player: no control characters, no BBCode, no direction
## overrides (which reverse what follows), at most `max_length` long.
static func clean_text(text: String, max_length: int = CHAT_MAX) -> String:
	text = text.left(max_length * 4)
	var result := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 9 or c == 10 or c == 13:
			c = 32 # (a line break or a tab: one line)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xa0) or (c >= 0x202a and c <= 0x202e) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0x200b or c == 0xfeff:
			continue
		result += char(c)
	result = _bbcode.sub(result, "", true)
	return result.strip_edges().left(max_length)


static func valid_name(text: String) -> bool:
	return _name_pattern.search(text) != null


## The name this player joins with: Player Settings allow any letters, a
## server wants A-Z, digits and _ (Russian letters spelled in Latin ones).
static func network_name(text: String) -> String:
	var result := ""
	for i in text.length():
		var c := text[i]
		var lower := c.to_lower()
		if CYRILLIC.has(lower):
			var latin: String = CYRILLIC[lower]
			result += latin.capitalize() if c != lower and latin != "" else latin
		elif _name_pattern.search("aa" + c) != null:
			result += c
		elif c == " " or c == "-" or c == ".":
			result += "_"
	result = result.left(NAME_MAX)
	while result.length() < NAME_MIN:
		result += "_" if result != "" else "Player"
	return result.left(NAME_MAX)


static func finite(v: Vector3) -> bool:
	return v.is_finite()


## A point a player could be at: finite and inside the world's bounds.
static func in_world(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < WORLD_LIMIT and absf(v.z) < WORLD_LIMIT and v.y > Y_MIN and v.y < Y_MAX


static func in_world_i(v: Vector3i) -> bool:
	return absi(v.x) < int(WORLD_LIMIT) and absi(v.z) < int(WORLD_LIMIT) and v.y >= -64 and v.y < 1024


## Distance from a point to the nearest point of the block at `pos`.
static func distance_to_block(from: Vector3, pos: Vector3i) -> float:
	var box := AABB(Vector3(pos), Vector3.ONE)
	var nearest := Vector3(clampf(from.x, box.position.x, box.end.x), clampf(from.y, box.position.y, box.end.y),
		clampf(from.z, box.position.z, box.end.z))
	return from.distance_to(nearest)


## An item stack that may exist: a real id, 0 < count <= its stack size.
static func valid_stack(id: int, count: int, damage: int) -> bool:
	if id == Blocks.AIR:
		return count == 0
	return Items.exists(id) and count > 0 and count <= Items.max_stack(id) and damage >= 0 \
		and damage <= maxi(Items.durability(id), 255)


## Blocks a player in survival can't place or have: they only come from
## the world itself (bedrock, spawners, the dungeon chest's loot, a
## piston's moving block and head).
static func survival_forbidden(id: int) -> bool:
	if id <= Blocks.AIR or id >= Blocks.count():
		return id != Blocks.AIR
	var block := Blocks.get_type(id)
	if block.hardness < 0.0 and Blocks.liquid_table[id] == 0:
		return true
	var family := Blocks.family_of(id)
	return family in ["mob_spawner", "dungeon_chest", "piston_head", "moving_piston"]


## Blocks nobody (not even creative) may break in survival.
static func unbreakable(id: int) -> bool:
	return id > Blocks.AIR and id < Blocks.count() and Blocks.get_type(id).hardness < 0.0 and Blocks.liquid_table[id] == 0


## A saved inventory from a client made safe: `size` slots of real stacks.
static func clean_inventory(value: Variant, size: int) -> Dictionary:
	var ids := PackedInt32Array()
	var counts := PackedInt32Array()
	var damages := PackedInt32Array()
	ids.resize(size)
	counts.resize(size)
	damages.resize(size)
	if value is Dictionary:
		var saved: Dictionary = value
		var base: int = int(saved.get("item_base", Items.FIRST_ITEM)) if saved.get("item_base", 0) is int else Items.FIRST_ITEM
		var in_ids: Variant = saved.get("ids")
		var in_counts: Variant = saved.get("counts")
		var in_damages: Variant = saved.get("damages")
		if in_ids is PackedInt32Array and in_counts is PackedInt32Array:
			for slot in mini(size, mini((in_ids as PackedInt32Array).size(), (in_counts as PackedInt32Array).size())):
				var id := Items.from_save(in_ids[slot], base)
				var count: int = in_counts[slot]
				var damage: int = in_damages[slot] if in_damages is PackedInt32Array and slot < (in_damages as PackedInt32Array).size() else 0
				if id != Blocks.AIR and valid_stack(id, count, damage):
					ids[slot] = id
					counts[slot] = count
					damages[slot] = damage
	return {"ids": ids, "counts": counts, "damages": damages, "item_base": Items.FIRST_ITEM}


## A client's player state (Player.save_state) made safe for the save:
## known keys of the right types only; the position is where the host saw
## it (a client can't save itself somewhere else and rejoin there).
static func clean_player_state(value: Variant, position: Vector3) -> Dictionary:
	if not value is Dictionary or var_to_bytes(value).size() > PLAYER_STATE_BYTES:
		return {}
	var state: Dictionary = value
	var result := {"position": position}
	result["yaw"] = _float(state.get("yaw"), 0.0)
	result["pitch"] = clampf(_float(state.get("pitch"), 0.0), -PI, PI)
	result["flying"] = state.get("flying") is bool and state.flying
	result["selected_slot"] = clampi(int(state.get("selected_slot")) if state.get("selected_slot") is int else 0, 0, Inventory.HOTBAR_SIZE - 1)
	result["health"] = clampi(int(state.get("health")) if state.get("health") is int else Player.MAX_HEALTH, 1, Player.MAX_HEALTH)
	var spawn: Variant = state.get("spawn")
	result["spawn"] = spawn if spawn is Vector3 and in_world(spawn) else Vector3.INF
	result["inventory"] = clean_inventory(state.get("inventory"), Inventory.SIZE)
	result["armor"] = clean_inventory(state.get("armor"), 4)
	return result


static func _float(value: Variant, default: float) -> float:
	if value is float and is_finite(value):
		return value
	if value is int:
		return float(value)
	return default


## An entity a client made (an arrow, a boat...) made safe: only keys the
## kind's own state has, with values of the same type; no inventory (a
## chest minecart's), fuel or health from the client.
static func clean_entity_state(state: Dictionary, defaults: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in defaults:
		if key in ["inventory", "fuel", "health", "age", "fire", "push"]:
			continue
		if state.has(key) and typeof(state[key]) == typeof(defaults[key]):
			var value: Variant = state[key]
			if value is float and not is_finite(value):
				continue
			if value is Vector3 and not (value as Vector3).is_finite():
				continue
			if value is String:
				value = (value as String).left(64)
			if value is Array or value is Dictionary:
				continue # (none needed; nothing nested from a client)
			result[key] = value
	result["type"] = defaults.get("type", "")
	return result


## A client's movement as the host sees it: how far it may go (by what it
## does) in the real time since its last state, with a little saved up for
## bursts (a knockback, a jump off a slime). Lag is allowed for: after a
## gap of up to GAP_SECONDS the whole gap's movement may come at once (the
## states held back arrive together, or only the last one does). Further
## than that is sent back to the last good place; only a long run of large
## ones (a speed hack does it all the time, lag a few times) is a kick.
## Ops are checked too: teleports go through the host.
class Mover:
	extends RefCounted
	## Blocks per second, horizontally and up; falling is free up to FALL.
	## (Walking is 4.3, flying in creative 11: room for the host seeing the
	## player late.)
	const WALK := 9.0
	const FLY := 26.0
	const RIDE := 30.0
	const UP := 7.0
	const FLY_UP := 14.0
	const FALL := 90.0
	## Movement saved up for a burst (blocks).
	const BURST := 10.0
	## The longest silence whose movement may arrive at once.
	const GAP_SECONDS := 5.0
	## A kick: more than VIOLATIONS counted corrections in VIOLATION_SECONDS,
	## the first at least SUSTAINED_SECONDS ago (one lag spike can't do it).
	const VIOLATIONS := 30
	const VIOLATION_SECONDS := 60.0
	const SUSTAINED_SECONDS := 15.0
	## After a correction or a teleport: how long states sent before the
	## client knew are ignored (the correction may arrive late).
	const CORRECTION_SECONDS := 5.0

	var position := Vector3.ZERO
	var time := 0.0
	var budget := BURST
	var budget_up := BURST
	## How far the last refused move went beyond what was allowed.
	var excess := 0.0
	## After a correction or a teleport: states until the client is there
	## again are ignored (they were sent before it knew).
	var waiting_for := Vector3.INF
	var waiting_until := 0.0
	var violations: Array[float] = []
	## The client never came back after the last correction (a changed
	## client ignoring it): its next violation counts IGNORED_WEIGHT times.
	var ignored_correction := false
	const IGNORED_WEIGHT := 5
	var dead := false

	func _init(at: Vector3, now: float) -> void:
		position = at
		time = now

	## Starts over at `at` (a teleport made by the host).
	func teleport(at: Vector3, now: float) -> void:
		position = at
		time = now
		budget = BURST
		budget_up = BURST
		waiting_for = at
		waiting_until = now + CORRECTION_SECONDS

	enum { ACCEPT, IGNORE, REJECT }

	## Whether moving to `at` now is allowed (`creative`: flying, `riding`
	## a boat or minecart): ACCEPT, IGNORE (a state sent before the client
	## knew of a correction) or REJECT (sent back to `position`).
	func check(at: Vector3, now: float, creative: bool, riding: bool) -> int:
		var gap := clampf(now - time, 0.0, GAP_SECONDS)
		time = now
		var speed := RIDE if riding else (FLY if creative else WALK)
		var up_speed := FLY_UP if creative or riding else UP
		# The allowance grows with the time gone by; what a long gap saved up
		# isn't cut by the quick states after it (they're the held-back ones).
		budget = minf(budget + speed * gap, maxf(budget, BURST + speed * maxf(gap, 1.0)))
		budget_up = minf(budget_up + up_speed * gap, maxf(budget_up, BURST + up_speed * maxf(gap, 1.0)))
		if waiting_for != Vector3.INF:
			if at.distance_to(waiting_for) < 3.0:
				waiting_for = Vector3.INF
				position = at
				return ACCEPT
			if now < waiting_until:
				return IGNORE
			waiting_for = Vector3.INF
			ignored_correction = true
		var horizontal := Vector2(at.x - position.x, at.z - position.z).length()
		var up := at.y - position.y
		var fall_allowed := FALL * maxf(gap, 0.05) + BURST
		if horizontal > budget or up > budget_up or -up > fall_allowed:
			excess = maxf(maxf(horizontal - budget, up - budget_up), -up - fall_allowed)
			return REJECT
		budget -= horizontal
		budget_up -= maxf(up, 0.0)
		position = at
		ignored_correction = false
		return ACCEPT

	## After a REJECT: the client is sent back and its states ignored until
	## it is there. Counts the violation; true when there were too many for
	## too long (a kick).
	func violated(now: float) -> bool:
		waiting_for = position
		waiting_until = now + CORRECTION_SECONDS
		for i in IGNORED_WEIGHT if ignored_correction else 1:
			violations.append(now)
		while not violations.is_empty() and now - violations[0] > VIOLATION_SECONDS:
			violations.pop_front()
		return violations.size() > VIOLATIONS and now - violations[0] >= SUSTAINED_SECONDS
