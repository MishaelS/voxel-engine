class_name SignBehavior
extends RefCounted
## Signs like the classic game: a sign post on the floor (16 directions)
## or a sign on a wall, with 4 lines of up to 15 letters (its block entity;
## written right after placing it, SignEditScreen; drawn by SignTexts).
## A sign post needs a solid block under it (wall signs: TorchBehavior).

const LINES := 4
const LINE_LENGTH := 15


static func is_sign(id: int) -> bool:
	var family := Blocks.family_of(id)
	return family == "sign" or family == "wall_sign"


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	if not TorchBehavior.can_hold(world, pos + Vector3i.DOWN):
		world.destroy_block(pos, true, true)


## Where the text is drawn (middle of the board's front) and the board's
## turn around Y (radians), for a sign block.
static func text_place(id: int) -> Array:
	var turn := 0.0
	var front := Vector3(0.5, 13.33 / 16.0, 8.67 / 16.0 + 0.004)
	if Blocks.family_of(id) == "wall_sign":
		turn = deg_to_rad(BlockModel.FACING_TURNS[Blocks.facing_table[id]])
		front = Vector3(0.5, 8.33 / 16.0, 1.67 / 16.0 + 0.004)
	else:
		turn = deg_to_rad(-Blocks.family_ids("sign").find(id) * 22.5)
	var middle := Vector3(0.5, 0.0, 0.5)
	return [Basis(Vector3.UP, turn) * (front - middle) + middle, turn]
