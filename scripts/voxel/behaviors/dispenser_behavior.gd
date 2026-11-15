class_name DispenserBehavior
extends RefCounted
## Dispensers like Beta 1.7.3: a block facing the player when placed, with 9
## slots (right-click opens them). When power reaches it (a rising edge, 4
## ticks later) it throws out one item from a random filled slot through its
## front: arrows fly out as arrows, snowballs and eggs as snowballs and
## eggs (ThrownItem), everything else is thrown as an item;
## smoke puffs out and it clicks. Empty, it only clicks.

const DELAY := 4


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var powered := Redstone.indirectly_powered(world, pos) or Redstone.indirectly_powered(world, pos + Vector3i.UP)
	if Redstone.edge(world, pos, powered) > 0:
		world.schedule_tick(pos, DELAY)


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if Blocks.family_of(id) != "dispenser":
		return
	var entity := world.block_entity(pos)
	if entity.is_empty():
		return
	var inventory: Inventory = entity.inventory
	var facing := Blocks.facing_table[id]
	# 4 / 5: facing up / down (placed looking down / up, like the modern game).
	var front := Blocks.FACING_DIRECTIONS[facing] if facing < 4 else (Vector3i.UP if facing == 4 else Vector3i.DOWN)
	var filled: Array[int] = []
	for slot in inventory.size():
		if inventory.count_at(slot) > 0:
			filled.append(slot)
	var mouth := Vector3(pos) + Vector3(0.5, 0.5, 0.5) + Vector3(front) * 0.6
	if filled.is_empty():
		Sounds.play("random/click", mouth, 1.0, 1.2)
		return
	var slot := filled[randi_range(0, filled.size() - 1)]
	var item := inventory.id_at(slot)
	var damage := inventory.damage_at(slot)
	inventory.take(slot)
	if Items.name_of(item) == "snowball" or Items.name_of(item) == "egg":
		# Beta: shot out as snowballs and eggs (1.1 a tick, spread 6), not dropped.
		ThrownItem.throw(world, Items.name_of(item), mouth - Vector3(0, 0.125, 0), Vector3(front) + Vector3(0, 0.1, 0), null, 1.1, 6.0)
	elif Items.name_of(item) == "arrow":
		var arrow := Arrow.shoot(world, mouth, mouth + Vector3(front) * 10.0 + Vector3(0, 1, 0), 1.1, 6.0, null)
		arrow.velocity = (Vector3(front) + Vector3(0, 0.1, 0)).normalized() * 1.1 \
			+ Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075 * 6.0
	else:
		var speed := randf() * 0.1 + 0.2
		var velocity := Vector3(front) * speed + Vector3(randfn(0, 1) * 0.045, 0.2 + randfn(0, 1) * 0.045, randfn(0, 1) * 0.045)
		world.items.spawn(item, 1, mouth - Vector3(0, 0.15, 0), velocity, ItemEntities.PICKUP_DELAY, damage)
		Sounds.play("random/click", mouth, 1.0, 1.0)
	for i in 6:
		world.particles.smoke(mouth + Vector3(front) * randf() * 0.4, 1)
