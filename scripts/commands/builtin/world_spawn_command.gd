class_name WorldSpawnCommand
extends RefCounted
## /setworldspawn [<pos>]  - where players appear and respawn without a bed
## (the executor's block by default; saved with the world).
## /difficulty [peaceful|easy|normal|hard]  - shows or sets the difficulty
## (the Difficulty option; also 0..3 and p / e / n / h).

const DIFFICULTIES := ["peaceful", "easy", "normal", "hard"]
const SHORT := {"p": 0, "e": 1, "n": 2, "h": 3, "0": 0, "1": 1, "2": 2, "3": 3}


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("setworldspawn").describe("Sets the world spawn")
		.executes(func(ctx: CommandContext) -> int: return _set_spawn(ctx, Vector3i(ctx.source.position().floor())))
		.then(CommandNode.argument("pos", PositionArgument.new(true)).executes(func(ctx: CommandContext) -> int:
			return _set_spawn(ctx, ctx.arg("pos")))))

	var choices := PackedStringArray(DIFFICULTIES)
	choices.append_array(PackedStringArray(SHORT.keys()))
	d.register(CommandNode.literal("difficulty").describe("Sets the difficulty level")
		.executes(func(ctx: CommandContext) -> int:
			var current: int = Settings.get_value("difficulty")
			return ctx.feedback(Lang.t("The difficulty is %s") % _name(current)))
		.then(CommandNode.argument("difficulty", ChoiceArgument.new(choices, "difficulty")).executes(func(ctx: CommandContext) -> int:
			var wanted: String = ctx.arg("difficulty")
			var level: int = SHORT[wanted] if SHORT.has(wanted) else DIFFICULTIES.find(wanted)
			if Settings.get_value("difficulty") == level:
				return ctx.error(Lang.t("The difficulty did not change; it is already set to %s") % _name(level))
			Settings.set_value("difficulty", level)
			return ctx.feedback(Lang.t("The difficulty has been set to %s") % _name(level)))))


static func _name(level: int) -> String:
	return Lang.t((DIFFICULTIES[clampi(level, 0, 3)] as String).capitalize())


static func _set_spawn(ctx: CommandContext, pos: Vector3i) -> int:
	var world := ctx.source.world
	world.world_spawn = Vector3(pos) + Vector3(0.5, 0.0, 0.5)
	return ctx.feedback(Lang.t("Set the world spawn point to %d, %d, %d") % [pos.x, pos.y, pos.z])
