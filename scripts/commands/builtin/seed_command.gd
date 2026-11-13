class_name SeedCommand
extends RefCounted
## /seed  - shows the world seed


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("seed").describe("Shows the world seed")
		.executes(func(ctx: CommandContext) -> int:
			return ctx.feedback(Lang.t("Seed: [%d]") % ctx.source.world.world_seed)))
