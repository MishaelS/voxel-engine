class_name FillCommand
extends RefCounted
## /fill <from> <to> <block> [replace [<filter>]|destroy|hollow|keep|outline]
## fills a box (up to MAX_VOLUME blocks):
##   replace: every block (or only <filter> blocks); destroy: breaks the old
##   blocks first (they drop); keep: only air; hollow: the shell, the
##   inside emptied; outline: only the shell.

const MAX_VOLUME := 32768
const MODES: Array[String] = ["destroy", "hollow", "keep", "outline"]


static func register(d: CommandDispatcher) -> void:
	var block_node := CommandNode.argument("block", BlockArgument.new()) \
		.executes(func(ctx: CommandContext) -> int: return _fill(ctx, "replace", -1)) \
		.then(CommandNode.literal("replace")
			.executes(func(ctx: CommandContext) -> int: return _fill(ctx, "replace", -1))
			.then(CommandNode.argument("filter", BlockArgument.new()).executes(func(ctx: CommandContext) -> int:
				return _fill(ctx, "replace", ctx.arg("filter")))))
	for mode in MODES:
		block_node.then(CommandNode.literal(mode).executes(func(ctx: CommandContext) -> int: return _fill(ctx, mode, -1)))
	d.register(CommandNode.literal("fill").describe("Fills a region with a block")
		.then(CommandNode.argument("from", PositionArgument.new(true))
			.then(CommandNode.argument("to", PositionArgument.new(true))
				.then(block_node))))


static func _fill(ctx: CommandContext, mode: String, filter: int) -> int:
	var a: Vector3i = ctx.arg("from")
	var b: Vector3i = ctx.arg("to")
	var low := a.min(b)
	var high := a.max(b)
	var size := high - low + Vector3i.ONE
	var volume := size.x * size.y * size.z
	if volume > MAX_VOLUME:
		return ctx.error(Lang.t("Too many blocks in the specified area (maximum %d, specified %d)") % [MAX_VOLUME, volume])
	var world := ctx.source.world
	var block: int = ctx.arg("block")
	var changed := 0
	world.begin_batch() # the light all together at the end
	for y in range(low.y, high.y + 1):
		for z in range(low.z, high.z + 1):
			for x in range(low.x, high.x + 1):
				var pos := Vector3i(x, y, z)
				if not world.is_inside(pos):
					continue
				var shell := x == low.x or x == high.x or y == low.y or y == high.y or z == low.z or z == high.z
				var wanted := block
				var old := world.get_block(pos)
				match mode:
					"replace":
						if filter >= 0 and old != filter:
							continue
					"keep":
						if old != Blocks.AIR:
							continue
					"hollow":
						wanted = block if shell else Blocks.AIR
					"outline":
						if not shell:
							continue
				if old == wanted:
					continue
				if mode == "destroy" and old != Blocks.AIR:
					world.destroy_block(pos)
				world.set_block(pos, wanted)
				changed += 1
	world.end_batch()
	if changed == 0:
		return ctx.error(Lang.t("No blocks were filled"))
	return ctx.feedback(Lang.t("Successfully filled %d block(s)") % changed)
