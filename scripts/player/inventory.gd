class_name Inventory
extends RefCounted
## A set of item slots, like the classic game: the player's 36 slots (the
## first 9 are the hotbar, 27 more the main inventory), a chest's 27 or a
## furnace's 3. Each slot holds one stack: an item id (Items: blocks and
## items), a count (up to the item's max stack) and, for tools, the uses
## spent (damage).

signal changed

const SIZE := 36
const HOTBAR_SIZE := 9
const MAX_STACK := 64

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var damages := PackedInt32Array()


func _init(size: int = SIZE) -> void:
	ids.resize(size)
	counts.resize(size)
	damages.resize(size)


func size() -> int:
	return ids.size()


func is_empty_slot(slot: int) -> bool:
	return counts[slot] <= 0


func id_at(slot: int) -> int:
	return ids[slot] if counts[slot] > 0 else Blocks.AIR


func count_at(slot: int) -> int:
	return counts[slot]


func damage_at(slot: int) -> int:
	return damages[slot] if counts[slot] > 0 else 0


func set_slot(slot: int, id: int, count: int, damage: int = 0) -> void:
	if count <= 0 or id == Blocks.AIR:
		id = Blocks.AIR
		count = 0
		damage = 0
	ids[slot] = id
	counts[slot] = mini(count, Items.max_stack(id))
	damages[slot] = damage
	changed.emit()


func clear() -> void:
	ids.fill(0)
	counts.fill(0)
	damages.fill(0)
	changed.emit()


func is_empty() -> bool:
	for count in counts:
		if count > 0:
			return false
	return true


## Adds items like picking them up: first onto existing stacks of the same
## item, then into empty slots, hotbar first. Returns what did not fit.
func add(id: int, count: int, damage: int = 0) -> int:
	if id == Blocks.AIR or count <= 0:
		return 0
	var stack := Items.max_stack(id)
	for slot in ids.size():
		if count == 0:
			break
		if counts[slot] > 0 and ids[slot] == id and damages[slot] == damage and counts[slot] < stack:
			var moved := mini(count, stack - counts[slot])
			counts[slot] += moved
			count -= moved
	for slot in ids.size():
		if count == 0:
			break
		if counts[slot] <= 0:
			var moved := mini(count, stack)
			ids[slot] = id
			counts[slot] = moved
			damages[slot] = damage
			count -= moved
	changed.emit()
	return count


## How many of `count` items would fit (for picking up).
func room_for(id: int, damage: int = 0) -> int:
	var stack := Items.max_stack(id)
	var room := 0
	for slot in ids.size():
		if counts[slot] <= 0:
			room += stack
		elif ids[slot] == id and damages[slot] == damage:
			room += maxi(stack - counts[slot], 0)
	return room


## Takes `count` items from a slot (placing a block in survival).
func take(slot: int, count: int = 1) -> void:
	counts[slot] = maxi(counts[slot] - count, 0)
	if counts[slot] == 0:
		ids[slot] = Blocks.AIR
		damages[slot] = 0
	changed.emit()


## Uses a tool (or wears armor) in a slot: it breaks after its durability
## (survival), with the classic snap. Returns true if it broke.
func wear(slot: int, amount: int = 1) -> bool:
	var durability := Items.durability(id_at(slot))
	if durability <= 0:
		return false
	damages[slot] += amount
	if damages[slot] >= durability:
		set_slot(slot, Blocks.AIR, 0)
		Sounds.play("random/break", null, 0.8, randf_range(0.8, 1.2))
		return true
	changed.emit()
	return false


## First slot holding the item, or -1. `from`..`to` limits the search.
func find(id: int, from: int = 0, to: int = -1) -> int:
	if to < 0:
		to = ids.size()
	for slot in range(from, to):
		if counts[slot] > 0 and ids[slot] == id:
			return slot
	return -1


func swap(a: int, b: int) -> void:
	var id := ids[a]
	var count := counts[a]
	var damage := damages[a]
	ids[a] = ids[b]
	counts[a] = counts[b]
	damages[a] = damages[b]
	ids[b] = id
	counts[b] = count
	damages[b] = damage
	changed.emit()


## For saves: {"ids", "counts", "damages"}.
func save_state() -> Dictionary:
	return {"ids": ids, "counts": counts, "damages": damages, "item_base": Items.FIRST_ITEM}


## Restores a saved state; items that no longer exist are dropped.
func load_state(saved: Dictionary) -> void:
	var saved_ids: PackedInt32Array = saved.get("ids", PackedInt32Array())
	var saved_counts: PackedInt32Array = saved.get("counts", PackedInt32Array())
	var saved_damages: PackedInt32Array = saved.get("damages", PackedInt32Array())
	var base: int = saved.get("item_base", Items.OLD_FIRST_ITEM)
	for slot in mini(saved_ids.size(), ids.size()):
		var id := Items.from_save(saved_ids[slot], base)
		if not Items.exists(id):
			id = Blocks.AIR
		ids[slot] = id
		counts[slot] = mini(saved_counts[slot] if slot < saved_counts.size() else 0, Items.max_stack(id)) if id != Blocks.AIR else 0
		damages[slot] = saved_damages[slot] if slot < saved_damages.size() else 0
	changed.emit()
