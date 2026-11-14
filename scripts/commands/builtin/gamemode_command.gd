class_name GameModeCommand
extends RefCounted
## /gamemode <survival|creative> [<targets>]  - sets the game mode of the
## executor or of the players given (also accepts 0 / 1 and s / c like the
## classic game). The host (a server) changes the network game's other
## players too: the host keeps everyone's game mode (Net.set_peer_game_mode).

const MODES := {
	"survival": Player.GameMode.SURVIVAL, "s": Player.GameMode.SURVIVAL, "0": Player.GameMode.SURVIVAL,
	"creative": Player.GameMode.CREATIVE, "c": Player.GameMode.CREATIVE, "1": Player.GameMode.CREATIVE,
}


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("gamemode").describe("Sets the game mode")
		.then(CommandNode.argument("mode", ChoiceArgument.new(MODES.keys(), "game mode"))
			.executes(func(ctx: CommandContext) -> int:
				return _change(ctx, [ctx.source.origin] if ctx.source.origin else []))
			.then(CommandNode.argument("targets", EntityArgument.new(false, true)).executes(func(ctx: CommandContext) -> int:
				return _change(ctx, ctx.targets("targets"))))))


static func _change(ctx: CommandContext, targets: Array) -> int:
	var changed := 0
	var mode: Player.GameMode = MODES[ctx.arg("mode")]
	var mode_name := Lang.t((Player.GameMode.keys()[mode] as String).capitalize())
	for target: Variant in targets:
		if target is RemotePlayer and Net.is_host():
			Net.set_peer_game_mode((target as RemotePlayer).peer_id, mode)
			changed += 1
			if target == ctx.source.origin:
				ctx.feedback(Lang.t("Set own game mode to %s Mode") % mode_name)
			else:
				ctx.feedback(Lang.t("Set %s's game mode to %s Mode") % [CommandTargets.name_of(target), mode_name])
			continue
		if not target is Player:
			continue
		var player := target as Player
		player.game_mode = mode
		changed += 1
		if player == ctx.source.origin:
			ctx.feedback(Lang.t("Set own game mode to %s Mode") % mode_name)
		else:
			ctx.feedback(Lang.t("Set %s's game mode to %s Mode") % [CommandTargets.name_of(player), mode_name])
	if changed == 0:
		return ctx.error(Lang.t("No player to change"))
	return changed
