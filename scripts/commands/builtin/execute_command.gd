class_name ExecuteCommand
extends RefCounted
## /execute <part>... run <command>  - runs a command as, at or under
## conditions of other things, like the classic game. Parts, chained in any
## order (each changes who / where / which way the rest runs):
##   as <targets>             each target becomes the executor (@s)
##   at <targets>             at each target's position and facing
##   positioned <pos> | positioned as <targets>
##   rotated <yaw pitch> | rotated as <targets>
##   facing <pos> | facing entity <targets>   turned to look at it
##   align <axes>             the position floored on those axes (e.g. xz)
##   if|unless block <pos> <block>
##   if|unless blocks <begin> <end> <destination> all|masked
##   if|unless entity <targets>
## Ending with an if / unless part only tests: "Test passed" / "failed".
## e.g. /execute as @e[type=pig] at @s run setblock ~ ~-1 ~ gold_block

const ALIGN_AXES: Array[String] = ["x", "y", "z", "xy", "xz", "yz", "yx", "zx", "zy",
	"xyz", "xzy", "yxz", "yzx", "zxy", "zyx"]


static func register(d: CommandDispatcher) -> void:
	var execute := CommandNode.literal("execute").describe("Runs a command as, at or if something")
	execute.then(CommandNode.literal("run").redirects(d.root))
	execute.then(CommandNode.literal("as")
		.then(CommandNode.argument("targets", EntityArgument.new()).redirects(execute, _as)))
	execute.then(CommandNode.literal("at")
		.then(CommandNode.argument("targets", EntityArgument.new()).redirects(execute, _at)))
	execute.then(CommandNode.literal("positioned")
		.then(CommandNode.argument("pos", PositionArgument.new()).redirects(execute, func(ctx: CommandContext) -> Array:
			var next := ctx.source.copy()
			next.position_override = ctx.arg("pos")
			return [next]))
		.then(CommandNode.literal("as")
			.then(CommandNode.argument("targets", EntityArgument.new()).redirects(execute, func(ctx: CommandContext) -> Array:
				var result := []
				for target: Variant in ctx.targets("targets"):
					var next := ctx.source.copy()
					next.position_override = CommandTargets.position_of(target)
					result.append(next)
				return result))))
	execute.then(CommandNode.literal("rotated")
		.then(CommandNode.argument("rotation", RotationArgument.new()).redirects(execute, func(ctx: CommandContext) -> Array:
			var next := ctx.source.copy()
			next.rotation_override = ctx.arg("rotation")
			return [next]))
		.then(CommandNode.literal("as")
			.then(CommandNode.argument("targets", EntityArgument.new()).redirects(execute, func(ctx: CommandContext) -> Array:
				var result := []
				for target: Variant in ctx.targets("targets"):
					var next := ctx.source.copy()
					next.rotation_override = CommandTargets.rotation_of(target)
					result.append(next)
				return result))))
	execute.then(CommandNode.literal("facing")
		.then(CommandNode.argument("pos", PositionArgument.new()).redirects(execute, func(ctx: CommandContext) -> Array:
			return [_facing(ctx.source, ctx.arg("pos"))]))
		.then(CommandNode.literal("entity")
			.then(CommandNode.argument("targets", EntityArgument.new()).redirects(execute, func(ctx: CommandContext) -> Array:
				var result := []
				for target: Variant in ctx.targets("targets"):
					result.append(_facing(ctx.source, CommandTargets.eyes_of(target)))
				return result))))
	execute.then(CommandNode.literal("align")
		.then(CommandNode.argument("axes", ChoiceArgument.new(ALIGN_AXES, "axes")).redirects(execute, func(ctx: CommandContext) -> Array:
			var next := ctx.source.copy()
			var position := ctx.source.position()
			for axis_name in (ctx.arg("axes") as String):
				var axis := "xyz".find(axis_name)
				position[axis] = floorf(position[axis])
			next.position_override = position
			return [next])))
	for negate: bool in [false, true]:
		execute.then(_condition(execute, negate))
	d.register(execute)


static func _as(ctx: CommandContext) -> Array:
	var result := []
	for target: Variant in ctx.targets("targets"):
		if target is Node3D:
			var next := ctx.source.copy()
			next.origin = target
			next.name = CommandTargets.name_of(target)
			result.append(next)
	return result


static func _at(ctx: CommandContext) -> Array:
	var result := []
	for target: Variant in ctx.targets("targets"):
		var next := ctx.source.copy()
		next.position_override = CommandTargets.position_of(target)
		next.rotation_override = CommandTargets.rotation_of(target)
		result.append(next)
	return result


## The source turned to look from its position (feet) at `point`.
static func _facing(source: CommandSource, point: Vector3) -> CommandSource:
	var next := source.copy()
	var to := point - source.position()
	var flat := Vector2(to.x, to.z).length()
	next.rotation_override = Vector2(rad_to_deg(atan2(-to.x, to.z)), rad_to_deg(-atan2(to.y, flat)))
	return next


## "if" / "unless" (negate) with block, blocks and entity tests: each one
## runs the rest when it holds, or ends the command with a test result.
static func _condition(execute: CommandNode, negate: bool) -> CommandNode:
	var node := CommandNode.literal("unless" if negate else "if")
	var block_test := func(ctx: CommandContext) -> int:
		var pos: Vector3i = ctx.arg("pos")
		var world := ctx.source.world
		return 1 if world.is_inside(pos) and world.get_block(pos) == ctx.arg("block") else 0
	var entity_test := func(ctx: CommandContext) -> int:
		return ctx.targets("targets").size()
	node.then(CommandNode.literal("block")
		.then(CommandNode.argument("pos", PositionArgument.new(true))
			.then(_test_node(CommandNode.argument("block", BlockArgument.new()), execute, block_test, negate))))
	node.then(CommandNode.literal("entity")
		.then(_test_node(CommandNode.argument("targets", EntityArgument.new()), execute, entity_test, negate)))
	var blocks := CommandNode.argument("destination", PositionArgument.new(true))
	for mode: String in ["all", "masked"]:
		blocks.then(_test_node(CommandNode.literal(mode), execute, func(ctx: CommandContext) -> int:
			return _blocks_match(ctx, mode == "masked"), negate))
	node.then(CommandNode.literal("blocks")
		.then(CommandNode.argument("begin", PositionArgument.new(true))
			.then(CommandNode.argument("end", PositionArgument.new(true))
				.then(blocks))))
	return node


## A condition node: the rest runs only when test(ctx) > 0 (== 0 negated);
## at the end it reports the result.
static func _test_node(node: CommandNode, execute: CommandNode, test: Callable, negate: bool) -> CommandNode:
	node.redirects(execute, func(ctx: CommandContext) -> Array: return [ctx.source] if (test.call(ctx) > 0) != negate else [])
	node.executes(func(ctx: CommandContext) -> int:
		var count: int = test.call(ctx)
		if (count > 0) == negate:
			return ctx.error(Lang.t("Test failed"))
		if count > 1 and not negate:
			ctx.feedback(Lang.t("Test passed, count: %d") % count)
			return count
		return ctx.feedback(Lang.t("Test passed")))
	return node


## The number of matching blocks if the two boxes match, else 0.
static func _blocks_match(ctx: CommandContext, masked: bool) -> int:
	var a: Vector3i = ctx.arg("begin")
	var b: Vector3i = ctx.arg("end")
	var low := a.min(b)
	var size := a.max(b) - low + Vector3i.ONE
	if size.x * size.y * size.z > CloneCommand.MAX_VOLUME:
		return 0
	var to: Vector3i = ctx.arg("destination")
	var world := ctx.source.world
	var count := 0
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var offset := Vector3i(x, y, z)
				var id := world.get_block(low + offset)
				if masked and id == Blocks.AIR:
					continue
				if world.get_block(to + offset) != id:
					return 0
				count += 1
	return maxi(count, 1)
