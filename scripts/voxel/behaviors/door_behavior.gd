class_name DoorBehavior
extends RefCounted
## Doors like the classic game: two blocks high (a lower and an upper
## half, each its own state: kind, half, open or closed, facing). The
## wooden door opens and closes by hand, the iron one only by redstone
## (later). Breaking either half takes the whole door (the lower half
## drops it); a door without solid ground under it falls apart.


static func is_door(id: int) -> bool:
	return Blocks.family_of(id).contains("_door_")


## [kind, half, open] of a door block.
static func parts(id: int) -> Array:
	var bits := Blocks.family_of(id).split("_")
	return [bits[0], bits[2], bits[3] == "open"]


static func door_id(kind: String, half: String, open: bool, facing: int) -> int:
	return Blocks.variant("%s_door_%s_%s" % [kind, half, "open" if open else "closed"], facing)


## Places a door with its lower half at `pos` facing `facing` (the panel on
## that side when closed); `hit`: where in the cell (x, z, 0..1) the
## cursor pointed, for the hinge. Returns false if there is no room.
static func place(world: VoxelWorld, pos: Vector3i, kind: String, facing: int, hit := Vector2(0.5, 0.5)) -> bool:
	for cell: Vector3i in [pos, pos + Vector3i.UP]:
		var there := world.get_block(cell)
		if not world.is_inside(cell) or (there != Blocks.AIR and Blocks.replaceable_table[there] == 0):
			return false
	if Blocks.is_opaque_table[world.get_block(pos + Vector3i.DOWN)] == 0:
		return false
	var open := false
	if hinge_flipped(world, pos, facing, hit):
		# Like the game's: the door hinged on the other side is an open door
		# turned a quarter (its panel lies on the same edge).
		facing = (facing + 3) % 4
		open = true
	world.set_block(pos + Vector3i.UP, door_id(kind, "upper", open, facing), false)
	world.set_block(pos, door_id(kind, "lower", open, facing))
	return true


## The side (a unit step) the hinges of a closed door facing `facing` are on.
static func hinge_side(facing: int) -> Vector3i:
	var turned := Basis(Vector3.UP, deg_to_rad(BlockModel.FACING_TURNS[facing])) * Vector3(-1, 0, 0)
	return Vector3i(roundi(turned.x), 0, roundi(turned.z))


## Whether a door placed at `pos` gets its hinges on the other side, like
## the modern game's (DoorBlock.getHinge): away from a lower door next to it
## (a double door, the two meet in the middle) or on the side with more
## full blocks; else on the half of the cell the cursor pointed at (`hit`:
## x, z in the cell).
static func hinge_flipped(world: VoxelWorld, pos: Vector3i, facing: int, hit := Vector2(0.5, 0.5)) -> bool:
	var side := hinge_side(facing)
	var solid_hinge := _full(world, pos + side) + _full(world, pos + side + Vector3i.UP)
	var solid_across := _full(world, pos - side) + _full(world, pos - side + Vector3i.UP)
	var door_at_hinge := _lower_door(world, pos + side)
	var door_across := _lower_door(world, pos - side)
	if (door_at_hinge and not door_across) or solid_across > solid_hinge:
		return true
	if (door_across and not door_at_hinge) or solid_hinge > solid_across:
		return false
	return Vector2(side.x, side.z).dot(hit - Vector2(0.5, 0.5)) < 0.0


## 1 for a full solid cube (glass too), else 0.
static func _full(world: VoxelWorld, pos: Vector3i) -> int:
	var id := world.get_block(pos)
	return 1 if Blocks.collides_table[id] == 1 and Blocks.shape_table[id] == BlockType.Shape.CUBE and Blocks.height_table[id] >= 1.0 else 0


static func _lower_door(world: VoxelWorld, pos: Vector3i) -> bool:
	var id := world.get_block(pos)
	return is_door(id) and parts(id)[1] == "lower"


## Opens or closes the door that `pos` is part of. Returns true if it did.
static func toggle(world: VoxelWorld, pos: Vector3i) -> bool:
	var id := world.get_block(pos)
	var info := parts(id)
	var lower: Vector3i = pos if info[1] == "lower" else pos + Vector3i.DOWN
	var lower_id := world.get_block(lower)
	if not is_door(lower_id):
		return false
	var lower_info := parts(lower_id)
	var facing := Blocks.facing_table[lower_id]
	var open: bool = not lower_info[2]
	world.set_block(lower + Vector3i.UP, door_id(lower_info[0], "upper", open, facing), false)
	world.set_block(lower, door_id(lower_info[0], "lower", open, facing), false)
	Sounds.play("door/" + ("open" if open else "close"), Vector3(lower) + Vector3(0.5, 1.0, 0.5), 1.0, randf() * 0.1 + 0.9)
	return true


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_door(id):
		return
	if parts(id)[1] == "lower":
		var upper_ok: bool = is_door(world.get_block(pos + Vector3i.UP)) and parts(world.get_block(pos + Vector3i.UP))[1] == "upper"
		if not upper_ok or Blocks.is_opaque_table[world.get_block(pos + Vector3i.DOWN)] == 0:
			world.destroy_block(pos, true, true)
	else:
		var below := world.get_block(pos + Vector3i.DOWN)
		if not is_door(below) or parts(below)[1] != "lower":
			world.set_block(pos, Blocks.AIR)
