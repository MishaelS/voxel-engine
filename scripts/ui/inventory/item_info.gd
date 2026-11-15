class_name ItemInfo
extends RefCounted
## What an item's tooltip says (InventoryScreen): its name, and with the
## left Ctrl held what the item does, like the modern game's tooltips -
## the hit in hand (green), armor (blue), healing, fuel, durability, a
## block's hardness and light, the stack size and its inner name.
## Beta has no attack speed: none is shown.

const NAME := Color.WHITE
const HEADER := Color("aaaaaa")  # "When in Main Hand:"
const STAT := Color("55ff55")    # what it does in hand (the game's dark green on dark: kept readable)
const ARMOR := Color("5555ff")   # armor, like the game's modifiers
const PLAIN := Color("ffffff")
const FAINT := Color("808080")   # the inner name, the Ctrl hint (lighter than the game's 555555: read on the dark)
const HEART := 2.0               # health points in a heart

const WORN_ON := ["When on Head:", "When on Body:", "When on Legs:", "When on Feet:"]


## [[text, color], ...] for the item `id` (`damage`: its wear); `details`:
## the left Ctrl is held.
static func lines(id: int, damage: int, details: bool) -> Array:
	var result := [[Items.display_name(id), NAME]]
	if Quiver.is_quiver(id):
		result.append([Lang.t("Arrows: %d / %d") % [clampi(damage, 0, Quiver.CAPACITY), Quiver.CAPACITY], HEADER])
	var more := _details(id, damage)
	if more.is_empty():
		return result
	if not details:
		result.append([Lang.t("Hold Left Ctrl for more"), FAINT])
		return result
	result.append_array(more)
	return result


static func _details(id: int, damage: int) -> Array:
	var result := []
	var item := Items.get_type(id) if not Items.is_block(id) else null
	if item:
		if item.armor_slot >= 0 and item.armor_slot < WORN_ON.size():
			result.append(["", PLAIN])
			result.append([Lang.t(WORN_ON[item.armor_slot]), HEADER])
			result.append([" " + Lang.t("+%d Armor") % item.armor, ARMOR])
		elif item.tool != "" or Items.attack_damage(id) > 1:
			result.append(["", PLAIN])
			result.append([Lang.t("When in Main Hand:"), HEADER])
			result.append([" " + Lang.t("%d Attack Damage") % Items.attack_damage(id), STAT])
			if item.tool in ["pickaxe", "axe", "shovel"] and item.efficiency > 1.0:
				result.append([" " + Lang.t("%s Mining Speed") % _number(item.efficiency), STAT])
		if item.heal > 0:
			result.append(["", PLAIN])
			result.append([Lang.t("When Eaten:"), HEADER])
			result.append([" " + Lang.t("+%s Hearts") % _number(item.heal / HEART), STAT])
	var block := Blocks.get_type(id) if Items.is_block(id) else null
	if block:
		result.append(["", PLAIN])
		if block.hardness >= 0.0:
			result.append([Lang.t("Hardness: %s") % _number(block.hardness), HEADER])
		else:
			result.append([Lang.t("Unbreakable"), HEADER])
		if block.light_emission > 0:
			result.append([Lang.t("Light: %d") % block.light_emission, HEADER])
	var fuel := Items.fuel_ticks(id)
	if fuel > 0:
		if block == null:
			result.append(["", PLAIN])
		result.append([Lang.t("Fuel: smelts %s items") % _number(fuel / 200.0), HEADER])
	if Quiver.is_quiver(id):
		result.append(["", PLAIN])
		result.append([Lang.t("Arrows go in with a click, out with a right click"), HEADER])
	var durability := Items.durability(id)
	if durability > 0:
		result.append(["", PLAIN])
		result.append([Lang.t("Durability: %d / %d") % [durability - damage, durability], PLAIN])
	var stack := Items.max_stack(id)
	if stack != 64:
		result.append([Lang.t("Stacks to %d") % stack, HEADER])
	if result.is_empty():
		result.append(["", PLAIN])
	result.append(["voxel:%s (#%d)" % [Items.name_of(id), id], FAINT])
	return result


## 1.5 -> "1.5", 2.0 -> "2".
static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))
