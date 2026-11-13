class_name TeleportCommand
extends RefCounted
## /tp <location>                          - moves the executor
## /tp <destination>                       - moves the executor to an entity
## /tp <targets> <location> [<rotation>]   - moves entities (and turns them)
## /tp <targets> <destination>             - moves entities to an entity
## /teleport is the same. Rotation is "yaw pitch" in degrees (~ relative).


static func register(d: CommandDispatcher) -> void:
	for command_name: String in ["tp", "teleport"]:
		d.register(CommandNode.literal(command_name).describe("Teleports entities")
			.then(CommandNode.argument("location", PositionArgument.new()).executes(func(ctx: CommandContext) -> int:
				return _teleport(ctx, _self(ctx), ctx.arg("location"), Vector2.INF, "")))
			.then(CommandNode.argument("targets", EntityArgument.new())
				.executes(func(ctx: CommandContext) -> int:
					# Alone it is the destination of the executor.
					var found := ctx.targets("targets")
					if found.size() > 1:
						return ctx.error(Lang.t("Only one entity is allowed, but the provided selector allows more than one"))
					if found.is_empty():
						return ctx.error(Lang.t("No entity was found"))
					return _teleport(ctx, _self(ctx), CommandTargets.position_of(found[0]), Vector2.INF,
						CommandTargets.name_of(found[0])))
				.then(CommandNode.argument("location", PositionArgument.new())
					.executes(func(ctx: CommandContext) -> int:
						return _teleport(ctx, ctx.targets("targets"), ctx.arg("location"), Vector2.INF, ""))
					.then(CommandNode.argument("rotation", RotationArgument.new()).executes(func(ctx: CommandContext) -> int:
						return _teleport(ctx, ctx.targets("targets"), ctx.arg("location"), ctx.arg("rotation"), ""))))
				.then(CommandNode.argument("destination", EntityArgument.new(true)).executes(func(ctx: CommandContext) -> int:
					var found := ctx.targets("destination")
					if found.is_empty():
						return ctx.error(Lang.t("No entity was found"))
					return _teleport(ctx, ctx.targets("targets"), CommandTargets.position_of(found[0]), Vector2.INF,
						CommandTargets.name_of(found[0]))))))


static func _self(ctx: CommandContext) -> Array:
	return [ctx.source.origin] if ctx.source.origin else []


## `to_name`: the destination entity's name ("" for a position).
static func _teleport(ctx: CommandContext, targets: Array, position: Vector3, rotation: Vector2, to_name: String) -> int:
	if targets.is_empty():
		return ctx.error(Lang.t("No entity was found"))
	var moved := []
	for target: Variant in targets:
		var problem := CommandTargets.teleport(target, position, rotation)
		if problem != "":
			ctx.error(problem)
		else:
			moved.append(CommandTargets.name_of(target))
	if moved.is_empty():
		return 0
	var where := to_name if to_name != "" else "%.2f, %.2f, %.2f" % [position.x, position.y, position.z]
	if moved.size() == 1:
		ctx.feedback(Lang.t("Teleported %s to %s") % [moved[0], where])
	else:
		ctx.feedback(Lang.t("Teleported %d entities to %s") % [moved.size(), where])
	return moved.size()
