class_name FillCommand
extends RefCounted
## /fill <from> <to> <block>  - fills a box (up to MAX_VOLUME blocks)

const MAX_VOLUME := 32768


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("fill").describe("Fills a region with a block")
		.then(CommandNode.argument("from", PositionArgument.new(true))
			.then(CommandNode.argument("to", PositionArgument.new(true))
				.then(CommandNode.argument("block", BlockArgument.new()).executes(_fill)))))


static func _fill(ctx: CommandContext) -> int:
	var a: Vector3i = ctx.arg("from")
	var b: Vector3i = ctx.arg("to")
	var low := a.min(b)
	var high := a.max(b)
	var size := high - low + Vector3i.ONE
	var volume := size.x * size.y * size.z
	if volume > MAX_VOLUME:
		return ctx.error("Too many blocks in the specified area (maximum %d, specified %d)" % [MAX_VOLUME, volume])
	var world := ctx.source.world
	var block: int = ctx.arg("block")
	var changed := 0
	world.begin_batch() # the light all together at the end
	for y in range(low.y, high.y + 1):
		for z in range(low.z, high.z + 1):
			for x in range(low.x, high.x + 1):
				var pos := Vector3i(x, y, z)
				if world.is_inside(pos) and world.get_block(pos) != block:
					world.set_block(pos, block)
					changed += 1
	world.end_batch()
	if changed == 0:
		return ctx.error("No blocks were filled")
	return ctx.feedback("Successfully filled %d block(s)" % changed)
