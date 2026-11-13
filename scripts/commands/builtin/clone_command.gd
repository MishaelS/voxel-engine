class_name CloneCommand
extends RefCounted
## /clone <begin> <end> <destination> [replace|masked] [normal|force|move]
## copies a box of blocks (with chest, furnace and dispenser contents and
## sign texts) so that its lowest corner lands on <destination>:
##   replace: every block; masked: all but air;
##   normal: the boxes may not overlap; force: they may; move: the source
##   blocks left behind become air.

const MAX_VOLUME := 32768


static func register(d: CommandDispatcher) -> void:
	var destination := CommandNode.argument("destination", PositionArgument.new(true)) \
		.executes(func(ctx: CommandContext) -> int: return _clone(ctx, false, "normal"))
	for mask: String in ["replace", "masked"]:
		var mask_node := CommandNode.literal(mask) \
			.executes(func(ctx: CommandContext) -> int: return _clone(ctx, mask == "masked", "normal"))
		for flag: String in ["normal", "force", "move"]:
			mask_node.then(CommandNode.literal(flag).executes(func(ctx: CommandContext) -> int:
				return _clone(ctx, mask == "masked", flag)))
		destination.then(mask_node)
	d.register(CommandNode.literal("clone").describe("Copies blocks from one place to another")
		.then(CommandNode.argument("begin", PositionArgument.new(true))
			.then(CommandNode.argument("end", PositionArgument.new(true))
				.then(destination))))


static func _clone(ctx: CommandContext, masked: bool, flag: String) -> int:
	var a: Vector3i = ctx.arg("begin")
	var b: Vector3i = ctx.arg("end")
	var low := a.min(b)
	var size := a.max(b) - low + Vector3i.ONE
	var volume := size.x * size.y * size.z
	if volume > MAX_VOLUME:
		return ctx.error(Lang.t("Too many blocks in the specified area (maximum %d, specified %d)") % [MAX_VOLUME, volume])
	var to: Vector3i = ctx.arg("destination")
	var source_box := AABB(Vector3(low), Vector3(size))
	var target_box := AABB(Vector3(to), Vector3(size))
	if flag != "force" and source_box.intersects(target_box):
		return ctx.error(Lang.t("The source and destination areas cannot overlap"))
	var world := ctx.source.world
	# Everything is read first, so overlapping boxes copy right (force).
	var blocks := []
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var offset := Vector3i(x, y, z)
				var from := low + offset
				if not world.is_inside(from) or not world.is_inside(to + offset):
					return ctx.error(Lang.t("That position is not loaded"))
				var id := world.get_block(from)
				if masked and id == Blocks.AIR:
					continue
				blocks.append([offset, id, _entity_copy(world, from)])
	world.begin_batch()
	var changed := 0
	var written := {}
	for entry: Array in blocks:
		var pos: Vector3i = to + (entry[0] as Vector3i)
		written[pos] = true
		if world.get_block(pos) != entry[1]:
			world.set_block(pos, entry[1])
		_entity_paste(world, pos, entry[2])
		changed += 1
	if flag == "move":
		for entry: Array in blocks:
			var from: Vector3i = low + (entry[0] as Vector3i)
			if not written.has(from):
				world.set_block(from, Blocks.AIR)
	world.end_batch()
	if changed == 0:
		return ctx.error(Lang.t("No blocks were cloned"))
	return ctx.feedback(Lang.t("Successfully cloned %d block(s)") % changed)


## A block entity's state to copy ({} for none).
static func _entity_copy(world: VoxelWorld, pos: Vector3i) -> Dictionary:
	var entity := world.block_entity(pos)
	if entity.is_empty():
		return {}
	var result := entity.duplicate(true)
	if entity.has("inventory"):
		result.inventory = (entity.inventory as Inventory).save_state()
	return result


static func _entity_paste(world: VoxelWorld, pos: Vector3i, saved: Dictionary) -> void:
	if saved.is_empty():
		return
	if saved.type == "sign":
		world.set_sign_text(pos, (saved.lines as Array).duplicate())
		return
	var entity := world.block_entity(pos)
	if entity.is_empty():
		return
	for key: String in saved:
		if key == "inventory":
			(entity.inventory as Inventory).load_state(saved.inventory)
		elif key != "type":
			entity[key] = saved[key]
