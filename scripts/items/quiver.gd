class_name Quiver
extends RefCounted
## The quiver (ours: Beta's items.png had its picture, tile 38, but no
## item): holds up to CAPACITY arrows, kept in the item's own number (the
## inventory's "damage": it has no durability), so they go with it wherever
## it goes - dropped, saved, sent. Arrows go in and out in the inventory
## (InventoryScreen), the bow takes them from it before loose ones, and
## arrows picked up fill it.

const CAPACITY := 128
## Arrows taken out with one right click (a stack).
const TAKE_OUT := 64


static func is_quiver(id: int) -> bool:
	return id > Blocks.AIR and Items.name_of(id) == "quiver"


## Arrows in the quiver at `slot` (0 if it is no quiver).
static func arrows_at(inventory: Inventory, slot: int) -> int:
	if inventory.count_at(slot) <= 0 or not is_quiver(inventory.id_at(slot)):
		return 0
	return clampi(inventory.damage_at(slot), 0, CAPACITY)


## The first quiver in the inventory, -1 if none.
static func find(inventory: Inventory) -> int:
	for slot in inventory.size():
		if inventory.count_at(slot) > 0 and is_quiver(inventory.id_at(slot)):
			return slot
	return -1


## An arrow to shoot: in a quiver or loose.
static func has_arrow(inventory: Inventory) -> bool:
	for slot in inventory.size():
		if arrows_at(inventory, slot) > 0:
			return true
	return inventory.find(Items.id_of("arrow")) >= 0


## Takes an arrow to shoot: from a quiver first, then a loose one. False
## if there is none.
static func take_arrow(inventory: Inventory) -> bool:
	for slot in inventory.size():
		var arrows := arrows_at(inventory, slot)
		if arrows > 0:
			inventory.set_slot(slot, inventory.id_at(slot), 1, arrows - 1)
			return true
	var loose := inventory.find(Items.id_of("arrow"))
	if loose < 0:
		return false
	inventory.take(loose)
	return true


## Puts `count` arrows into the quivers there are (in order); returns how
## many did not fit.
static func store(inventory: Inventory, count: int) -> int:
	for slot in inventory.size():
		if count <= 0:
			break
		if inventory.count_at(slot) <= 0 or not is_quiver(inventory.id_at(slot)):
			continue
		var arrows := arrows_at(inventory, slot)
		var moved := mini(CAPACITY - arrows, count)
		if moved > 0:
			inventory.set_slot(slot, inventory.id_at(slot), 1, arrows + moved)
			count -= moved
	return count


## Room for arrows in all the quivers.
static func room(inventory: Inventory) -> int:
	var total := 0
	for slot in inventory.size():
		if inventory.count_at(slot) > 0 and is_quiver(inventory.id_at(slot)):
			total += CAPACITY - arrows_at(inventory, slot)
	return total
