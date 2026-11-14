class_name PistonBehavior
extends RefCounted
## Pistons and sticky pistons like Beta 1.7.3:
## - placed facing the player (up or down when looked at steeply);
## - powered from any side but the front - or, like the game's quirk, next
##   to the block above it - it pushes out its head, moving up to 12 blocks
##   in front of it one block on (and the creatures there with them);
##   plants, torches, wire, doors and the like in the way break and drop,
##   liquids are pushed aside;
## - it can't move obsidian, bedrock, extended pistons or blocks that keep
##   things (chests, furnaces, dispensers, jukeboxes, note blocks, signs);
## - unpowered it pulls the head back; a sticky one pulls the block in front
##   of the head along;
## - the head can't stay without its piston and breaking the head breaks the
##   piston too.
## - the blocks and the head slide over MOVE_TICKS like the game's: their
##   cells hold a "moving_piston" block (nothing to see, the block is drawn
##   sliding over it) that becomes the block when it arrives; a retracting
##   head slides back in.
## States: "piston"/"sticky_piston" dir * 2 + extended, "piston_head" dir *
## 2 + sticky, with dir in Redstone.DIRS order.

const PUSH_LIMIT := 12
## Ticks a pushed block takes to slide one block (the game's 0.5 a tick).
const MOVE_TICKS := 2


static func is_base(id: int) -> bool:
	var family := Blocks.family_of(id)
	return family == "piston" or family == "sticky_piston"


## [direction, extended, sticky] of a piston base.
static func base_info(id: int) -> Array:
	var family := Blocks.family_of(id)
	var index := Blocks.family_ids(family).find(id)
	return [Redstone.DIRS[index / 2], index % 2 == 1, family == "sticky_piston"]


static func base_id(direction: Vector3i, extended: bool, sticky: bool) -> int:
	return Blocks.family_ids("sticky_piston" if sticky else "piston")[Redstone.DIRS.find(direction) * 2 + (1 if extended else 0)]


static func head_info(id: int) -> Array:
	var index := Blocks.family_ids("piston_head").find(id)
	return [Redstone.DIRS[index / 2], index % 2 == 1]


static func head_id(direction: Vector3i, sticky: bool) -> int:
	return Blocks.family_ids("piston_head")[Redstone.DIRS.find(direction) * 2 + (1 if sticky else 0)]


## The way a piston (or dispenser) placed by someone looking along `look`
## faces: toward them along the axis they look closest to, like the modern
## game (up / down once the look is steeper than its horizontal parts).
static func facing_for(look: Vector3) -> Vector3i:
	if absf(look.y) > maxf(absf(look.x), absf(look.z)):
		return Vector3i.UP if look.y < 0.0 else Vector3i.DOWN
	if absf(look.x) > absf(look.z):
		return Vector3i(-1, 0, 0) if look.x > 0.0 else Vector3i(1, 0, 0)
	return Vector3i(0, 0, -1) if look.z > 0.0 else Vector3i(0, 0, 1)


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_base(id):
		return
	var info := base_info(id)
	var front := Blocks.family_of(world.get_block(pos + info[0]))
	if info[1] and front != "piston_head" and front != "moving_piston": # (the head may still be sliding out)
		world.set_block(pos, base_id(info[0], false, info[2]), false) # lost its head
		return
	if _powered(world, pos, info[0]) != info[1]:
		world.schedule_tick(pos, 1)


static func _powered(world: VoxelWorld, pos: Vector3i, front: Vector3i) -> bool:
	for d in Redstone.DIRS:
		if d != front and Redstone.provides(world, pos + d, -d):
			return true
	# The game's quirk: power next to the block above counts too.
	var above := pos + Vector3i.UP
	for d in Redstone.DIRS:
		if d != Vector3i.DOWN and Redstone.provides(world, above + d, -d):
			return true
	return false


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_base(id):
		return
	var info := base_info(id)
	var powered := _powered(world, pos, info[0])
	if powered and not info[1]:
		_extend(world, pos, info[0], info[2])
	elif not powered and info[1]:
		_retract(world, pos, info[0], info[2])


## What a push does to a block: "move", "break" (drops, makes room), "free"
## (air or liquid: room) or "stop".
static func mobility(world: VoxelWorld, pos: Vector3i) -> String:
	if pos.y < 0 or pos.y >= world.height or not world.is_inside(pos):
		return "stop"
	var id := world.get_block(pos)
	if id == Blocks.AIR or Blocks.liquid_table[id] == 1:
		return "free"
	var block := Blocks.get_type(id)
	var family := Blocks.family_of(id)
	if block.hardness < 0.0 or block.name == "obsidian" or family == "piston_head":
		return "stop"
	if is_base(id) and base_info(id)[1]:
		return "stop"
	if VoxelWorld._entity_type(id) != "" or family == "dungeon_chest" or family.begins_with("mob_spawner") \
			or family == "moving_piston":
		return "stop"
	if Blocks.collides_table[id] == 0 or DoorBehavior.is_door(id) or block.name == "cactus" or family == "cake":
		return "break"
	return "move"


static func _extend(world: VoxelWorld, pos: Vector3i, direction: Vector3i, sticky: bool) -> void:
	_finish_in_front(world, pos, direction)
	var moving: Array[Vector3i] = []
	var cell := pos + direction
	while true:
		var kind := mobility(world, cell)
		if kind == "stop":
			return
		if kind == "free" or kind == "break":
			break
		moving.append(cell)
		if moving.size() > PUSH_LIMIT:
			return
		cell += direction
	# `cell` is where the last block goes: clear it.
	if mobility(world, cell) == "break":
		world.destroy_block(cell, true, true)
	elif world.get_block(cell) != Blocks.AIR:
		world.set_block(cell, Blocks.AIR, false)
	for k in range(moving.size() - 1, -1, -1):
		var from := moving[k]
		start_moving(world, from + direction, world.get_block(from), from)
		world.set_block(from, Blocks.AIR)
	world.set_block(pos, base_id(direction, true, sticky), false) # first, so the head has its piston
	start_moving(world, pos + direction, head_id(direction, sticky), pos)
	_push_creatures(world, moving, pos + direction, direction)
	var player := world.player as Player
	if not moving.is_empty() and player and player.global_position.distance_to(Vector3(pos)) < 32.0:
		Stats.grant("engineer")
	Sounds.play("random/piston_out", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.5, randf() * 0.25 + 0.6)
	Redstone.notify_around(world, pos)


static func _retract(world: VoxelWorld, pos: Vector3i, direction: Vector3i, sticky: bool) -> void:
	_finish_in_front(world, pos, direction)
	var head := pos + direction
	world.set_block(pos, base_id(direction, false, sticky), false)
	if Blocks.family_of(world.get_block(head)) == "piston_head":
		_slide(world, world.get_block(head), head, pos) # the head slides back in
		world.set_block(head, Blocks.AIR)
	if sticky:
		var pulled := head + direction
		if mobility(world, pulled) == "move" and not (is_base(world.get_block(pulled)) and base_info(world.get_block(pulled))[1]):
			start_moving(world, head, world.get_block(pulled), pulled)
			world.set_block(pulled, Blocks.AIR)
	Sounds.play("random/piston_in", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.5, randf() * 0.15 + 0.6)
	Redstone.notify_around(world, pos)


## Creatures and the player standing where blocks (or the head) moved go
## along with them.
static func _push_creatures(world: VoxelWorld, moved: Array[Vector3i], head: Vector3i, direction: Vector3i) -> void:
	var cells: Array[Vector3i] = [head]
	for cell in moved:
		cells.append(cell + direction)
	var boxes: Array[AABB] = []
	for cell in cells:
		boxes.append(AABB(Vector3(cell), Vector3.ONE))
	var player := world.player as Player
	if player:
		var body := AABB(player.global_position - Vector3(Player.HALF_WIDTH, 0, Player.HALF_WIDTH),
			Vector3(Player.HALF_WIDTH * 2, Player.HEIGHT, Player.HALF_WIDTH * 2))
		for box in boxes:
			if box.intersects(body):
				player.global_position += Vector3(direction)
				break
	for entity in world.entities.all():
		for box in boxes:
			if box.intersects(entity.hit_box()):
				entity.teleport(entity.feet() + Vector3(direction))
				break


## The head goes without its extended piston.
static func on_head_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if Blocks.family_of(id) != "piston_head":
		return
	var direction: Vector3i = head_info(id)[0]
	var base := world.get_block(pos - direction)
	if not is_base(base) or not base_info(base)[1] or base_info(base)[0] != direction:
		world.set_block(pos, Blocks.AIR)


## Breaking the head breaks the piston behind it too (it drops).
static func head_broken(world: VoxelWorld, pos: Vector3i, id: int) -> void:
	var direction: Vector3i = head_info(id)[0]
	var base := pos - direction
	if is_base(world.get_block(base)):
		world.destroy_block(base, true, true)


# --- Sliding blocks ---------------------------------------------------------------------

## Starts `id` sliding from `from` into `to`: the cell holds a moving_piston
## block until it arrives (MOVE_TICKS), the block is drawn sliding.
static func start_moving(world: VoxelWorld, to: Vector3i, id: int, from: Vector3i) -> void:
	world.set_block(to, Blocks.id_of("moving_piston"), false)
	world.moving_blocks[to] = {"id": id, "node": _slide(world, id, from, to)}
	world.schedule_tick(to, MOVE_TICKS)


## Draws `id` sliding from `from` to `to` (gone when it arrives).
static func _slide(world: VoxelWorld, id: int, from: Vector3i, to: Vector3i) -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = FallingBlocks.block_mesh(id)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_instance_shader_parameter("entity_light", world.brightness_at(Vector3(to) + Vector3(0.5, 0.5, 0.5)))
	world.add_child(node)
	node.position = Vector3(from)
	var tween := node.create_tween()
	tween.tween_property(node, "position", Vector3(to), MOVE_TICKS / 20.0)
	tween.tween_callback(func() -> void:
		if not world.moving_blocks.values().any(func(entry: Dictionary) -> bool: return entry.node == node):
			node.queue_free()) # only the drawn-in head goes by itself
	return node


## The moving block arrived: it becomes the block (moving_piston's tick).
static func finish_moving(world: VoxelWorld, pos: Vector3i) -> void:
	var entry: Dictionary = world.moving_blocks.get(pos, {})
	world.moving_blocks.erase(pos)
	if not entry.is_empty() and is_instance_valid(entry.node):
		# Kept a moment until the chunk's new mesh with the arrived block is
		# up (built in the background): gone at once, the block blinked out.
		var node: Node = entry.node
		node.get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if is_instance_valid(node):
				node.queue_free())
	if Blocks.family_of(world.get_block(pos)) != "moving_piston":
		return
	world.set_block(pos, entry.get("id", Blocks.AIR))


## Like the game: blocks still sliding in front of a piston arrive at once
## before it moves again.
static func _finish_in_front(world: VoxelWorld, pos: Vector3i, direction: Vector3i) -> void:
	for k in range(1, PUSH_LIMIT + 3):
		var cell := pos + direction * k
		if world.moving_blocks.has(cell):
			finish_moving(world, cell)


## Every sliding block put in place at once (before saving).
static func finish_all(world: VoxelWorld) -> void:
	for pos: Vector3i in world.moving_blocks.keys():
		finish_moving(world, pos)
