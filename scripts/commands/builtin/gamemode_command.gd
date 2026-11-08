class_name GameModeCommand
extends RefCounted
## /gamemode <survival|creative>  - sets the player's game mode
## (also accepts 0 / 1 and s / c like the classic game).

const MODES := {
	"survival": Player.GameMode.SURVIVAL, "s": Player.GameMode.SURVIVAL, "0": Player.GameMode.SURVIVAL,
	"creative": Player.GameMode.CREATIVE, "c": Player.GameMode.CREATIVE, "1": Player.GameMode.CREATIVE,
}


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("gamemode").describe("Sets the game mode")
		.then(CommandNode.argument("mode", ChoiceArgument.new(MODES.keys(), "game mode"))
			.executes(func(ctx: CommandContext) -> int:
				var player := ctx.source.origin as Player
				if player == null:
					return ctx.error("No player to change")
				player.game_mode = MODES[ctx.arg("mode")]
				var name: String = Player.GameMode.keys()[player.game_mode].capitalize()
				return ctx.feedback("Set own game mode to %s Mode" % name))))
