class_name SetBlockCommand
extends RefCounted
## /setblock <pos> <block> [replace|keep|destroy]
## keep: only into air; destroy: breaks the old block first (it drops).


static func register(d: CommandDispatcher) -> void:
	var block_node := CommandNode.argument("block", BlockArgument.new()) \
		.executes(func(ctx: CommandContext) -> int: return _place(ctx, "replace"))
	for mode: String in ["replace", "keep", "destroy"]:
		block_node.then(CommandNode.literal(mode).executes(func(ctx: CommandContext) -> int: return _place(ctx, mode)))
	d.register(CommandNode.literal("setblock").describe("Changes a block")
		.then(CommandNode.argument("pos", PositionArgument.new(true)).then(block_node)))


static func _place(ctx: CommandContext, mode: String) -> int:
	var pos: Vector3i = ctx.arg("pos")
	var block: int = ctx.arg("block")
	var world := ctx.source.world
	if not world.is_inside(pos):
		return ctx.error(Lang.t("That position is not loaded"))
	var old := world.get_block(pos)
	if old == block or (mode == "keep" and old != Blocks.AIR):
		return ctx.error(Lang.t("Could not set the block"))
	if mode == "destroy" and old != Blocks.AIR:
		world.destroy_block(pos)
	world.set_block(pos, block)
	return ctx.feedback(Lang.t("Changed the block at %d, %d, %d") % [pos.x, pos.y, pos.z])
