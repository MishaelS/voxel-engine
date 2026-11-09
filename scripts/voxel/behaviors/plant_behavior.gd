class_name PlantBehavior
extends RefCounted
## Tall grass, ferns, flowers and dead bushes, like the classic game: when
## the ground under them goes (or changes to something they can't grow
## on), they break and drop what they give.


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not can_stay(id, world.get_block(pos + Vector3i.DOWN)):
		world.destroy_block(pos, true, true)


## Grass and dirt hold plants; sand holds dead bushes.
static func can_stay(plant: int, ground: int) -> bool:
	var ground_name := Blocks.get_type(ground).name
	if Blocks.get_type(plant).name == "dead_bush":
		return ground_name == "sand"
	return ground_name.begins_with("grass_") or ground_name == "dirt" or ground_name == "snowy_grass"
