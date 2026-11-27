class_name TrapdoorBehavior
extends RefCounted
## Trapdoors: hinged on the wall behind them, in the lower half of the cell
## (Beta's) or, like the modern game, in the upper half (placed against the
## upper half of a wall: "trapdoor_top"). Open, either one stands up
## against the wall; closed again it goes back to its half.

const FAMILIES: Array[String] = ["trapdoor", "trapdoor_open", "trapdoor_top", "trapdoor_top_open"]


static func is_trapdoor(family: String) -> bool:
	return family in FAMILIES


static func is_open(family: String) -> bool:
	return family.ends_with("_open")


## The same trapdoor (half and facing) opened or closed.
static func with_open(id: int, open: bool) -> int:
	var family := Blocks.family_of(id)
	var base := "trapdoor_top" if family.begins_with("trapdoor_top") else "trapdoor"
	return Blocks.variant(base + "_open" if open else base, Blocks.facing_table[id])


## Opens a closed trapdoor, closes an open one, with the door's sound.
static func toggle(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var open := not is_open(Blocks.family_of(id))
	world.set_block(pos, with_open(id, open))
	Sounds.play("door/" + ("open" if open else "close"), Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0, randf() * 0.1 + 0.9)
