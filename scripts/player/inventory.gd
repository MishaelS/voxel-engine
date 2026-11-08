class_name Inventory
extends RefCounted
## The player's items, like the classic game: 36 slots, the first 9 are the
## hotbar, 27 more are the main inventory. Each slot holds one stack: a
## block id and a count (up to MAX_STACK). For now every item is a block.

signal changed

const SIZE := 36
const HOTBAR_SIZE := 9
const MAX_STACK := 64

var ids := PackedInt32Array()
var counts := PackedInt32Array()


func _init() -> void:
	ids.resize(SIZE)
	counts.resize(SIZE)


func is_empty_slot(slot: int) -> bool:
	return counts[slot] <= 0


func id_at(slot: int) -> int:
	return ids[slot] if counts[slot] > 0 else Blocks.AIR


func count_at(slot: int) -> int:
	return counts[slot]


func set_slot(slot: int, id: int, count: int) -> void:
	if count <= 0 or id == Blocks.AIR:
		id = Blocks.AIR
		count = 0
	ids[slot] = id
	counts[slot] = mini(count, MAX_STACK)
	changed.emit()


func clear() -> void:
	ids.fill(0)
	counts.fill(0)
	changed.emit()


## Adds items like picking them up: first onto existing stacks of the same
## block, then into empty slots, hotbar first. Returns what did not fit.
func add(id: int, count: int) -> int:
	if id == Blocks.AIR or count <= 0:
		return 0
	for slot in SIZE:
		if count == 0:
			break
		if counts[slot] > 0 and ids[slot] == id and counts[slot] < MAX_STACK:
			var moved := mini(count, MAX_STACK - counts[slot])
			counts[slot] += moved
			count -= moved
	for slot in SIZE:
		if count == 0:
			break
		if counts[slot] <= 0:
			var moved := mini(count, MAX_STACK)
			ids[slot] = id
			counts[slot] = moved
			count -= moved
	changed.emit()
	return count


## Takes `count` items from a slot (placing a block in survival).
func take(slot: int, count: int = 1) -> void:
	counts[slot] = maxi(counts[slot] - count, 0)
	if counts[slot] == 0:
		ids[slot] = Blocks.AIR
	changed.emit()


## First slot holding the block, or -1. `from`..`to` limits the search.
func find(id: int, from: int = 0, to: int = SIZE) -> int:
	for slot in range(from, to):
		if counts[slot] > 0 and ids[slot] == id:
			return slot
	return -1


func swap(a: int, b: int) -> void:
	var id := ids[a]
	var count := counts[a]
	ids[a] = ids[b]
	counts[a] = counts[b]
	ids[b] = id
	counts[b] = count
	changed.emit()
