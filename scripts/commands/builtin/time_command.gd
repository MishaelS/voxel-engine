class_name TimeCommand
extends RefCounted
## /time set <time>|day|noon|night|midnight
## /time add <time>
## /time query daytime|gametime|day
## Time of day is in ticks: 0 = 06:00, 6000 = noon, 18000 = midnight.

const NAMED_TIMES := {"day": 1000, "noon": 6000, "night": 13000, "midnight": 18000}


static func register(d: CommandDispatcher) -> void:
	var set_node := CommandNode.literal("set") \
		.then(CommandNode.argument("time", TimeArgument.new()).executes(func(ctx: CommandContext) -> int:
			return _set_time(ctx, ctx.arg("time"))))
	for time_name: String in NAMED_TIMES:
		var ticks: int = NAMED_TIMES[time_name]
		set_node.then(CommandNode.literal(time_name).executes(func(ctx: CommandContext) -> int:
			return _set_time(ctx, ticks)))

	d.register(CommandNode.literal("time").describe("Changes or queries the world time")
		.then(set_node)
		.then(CommandNode.literal("add")
			.then(CommandNode.argument("time", TimeArgument.new()).executes(func(ctx: CommandContext) -> int:
				ctx.source.world.clock.add_day_time(ctx.arg("time"))
				return ctx.feedback("Set the time to %d" % int(ctx.source.world.clock.day_time)))))
		.then(CommandNode.literal("query")
			.then(CommandNode.literal("daytime").executes(func(ctx: CommandContext) -> int:
				return ctx.feedback("The time is %d" % int(ctx.source.world.clock.time_of_day()))))
			.then(CommandNode.literal("gametime").executes(func(ctx: CommandContext) -> int:
				return ctx.feedback("The time is %d" % ctx.source.world.clock.game_time)))
			.then(CommandNode.literal("day").executes(func(ctx: CommandContext) -> int:
				return ctx.feedback("The time is %d" % ctx.source.world.clock.day())))))


## Like the classic game: sets the time of the current day, keeps the day count.
static func _set_time(ctx: CommandContext, ticks: int) -> int:
	var clock := ctx.source.world.clock
	clock.day_time = clock.day() * WorldClock.TICKS_PER_DAY + ticks
	return ctx.feedback("Set the time to %d" % ticks)
