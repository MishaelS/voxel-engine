class_name TeleportCommand
extends RefCounted
## /tp <pos>  - moves the player (the camera for now)


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("tp").describe("Teleports the player")
		.then(CommandNode.argument("pos", PositionArgument.new()).executes(func(ctx: CommandContext) -> int:
			var pos: Vector3 = ctx.arg("pos")
			if ctx.source.origin == null:
				return ctx.error("Nothing to teleport")
			ctx.source.origin.global_position = pos
			return ctx.feedback("Teleported %s to %.2f, %.2f, %.2f" % [ctx.source.name, pos.x, pos.y, pos.z]))))
