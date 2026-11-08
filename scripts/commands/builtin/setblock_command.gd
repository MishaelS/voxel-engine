class_name SetBlockCommand
extends RefCounted
## /setblock <pos> <block>


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("setblock").describe("Changes a block")
		.then(CommandNode.argument("pos", PositionArgument.new(true))
			.then(CommandNode.argument("block", BlockArgument.new()).executes(func(ctx: CommandContext) -> int:
				var pos: Vector3i = ctx.arg("pos")
				var world := ctx.source.world
				if not world.is_inside(pos):
					return ctx.error("That position is not loaded")
				if world.get_block(pos) == ctx.arg("block"):
					return ctx.error("Could not set the block")
				world.set_block(pos, ctx.arg("block"))
				return ctx.feedback("Changed the block at %d, %d, %d" % [pos.x, pos.y, pos.z])))))
