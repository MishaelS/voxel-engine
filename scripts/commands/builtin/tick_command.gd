class_name TickCommand
extends RefCounted
## /tick query | freeze | unfreeze | step [<count>] | rate <ticks per second>


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("tick").describe("Controls the game tick loop")
		.then(CommandNode.literal("query").executes(func(ctx: CommandContext) -> int:
			return ctx.feedback("Target rate: %.1f TPS, measured: %.1f TPS, %.2f ms per tick%s" % [
				TickLoop.tick_rate, TickLoop.measured_tps, TickLoop.mspt, ", frozen" if TickLoop.frozen else ""])))
		.then(CommandNode.literal("freeze").executes(func(ctx: CommandContext) -> int:
			TickLoop.frozen = true
			return ctx.feedback("The game is frozen")))
		.then(CommandNode.literal("unfreeze").executes(func(ctx: CommandContext) -> int:
			TickLoop.frozen = false
			return ctx.feedback("The game is running")))
		.then(CommandNode.literal("step")
			.executes(func(ctx: CommandContext) -> int: return _step(ctx, 1))
			.then(CommandNode.argument("count", IntegerArgument.new(1, 100000)).executes(func(ctx: CommandContext) -> int:
				return _step(ctx, ctx.arg("count")))))
		.then(CommandNode.literal("rate")
			.then(CommandNode.argument("rate", FloatArgument.new(1.0, 1000.0)).executes(func(ctx: CommandContext) -> int:
				TickLoop.tick_rate = ctx.arg("rate")
				return ctx.feedback("Set the target tick rate to %.1f" % TickLoop.tick_rate)))))


static func _step(ctx: CommandContext, count: int) -> int:
	if not TickLoop.frozen:
		return ctx.error("The game must be frozen to step (/tick freeze)")
	TickLoop.step(count)
	return ctx.feedback("Stepping %d tick(s)" % count)
