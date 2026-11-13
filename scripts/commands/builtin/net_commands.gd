class_name NetCommands
extends RefCounted
## The host's commands in a network game:
## /players          - who is here, with their tags (#first 8 of the hash)
##                     and addresses
## /kick <player>    - sends a player away
## /ban <player>     - bans a player's tag (their computer) and kicks them
## /pardon <tag|name> - lifts a ban


static func register(d: CommandDispatcher) -> void:
	d.register(CommandNode.literal("players").describe("Lists the players and their tags (host)")
		.executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			return ctx.feedback(Net.describe_players())))
	d.register(CommandNode.literal("kick").describe("Sends a player away (host)")
		.then(CommandNode.argument("player", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.kick(ctx.arg("player"))
			return ctx.feedback(Lang.t("Kicked %s") % name) if name != "" else ctx.error(Lang.t("No such player")))))
	d.register(CommandNode.literal("ban").describe("Bans a player's computer from this server (host)")
		.then(CommandNode.argument("player", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.ban(ctx.arg("player"))
			return ctx.feedback(Lang.t("Banned %s") % name) if name != "" else ctx.error(Lang.t("No such player")))))
	d.register(CommandNode.literal("pardon").describe("Lifts a ban by tag or name (host)")
		.then(CommandNode.argument("tag", MessageArgument.new()).executes(func(ctx: CommandContext) -> int:
			if not Net.is_host():
				return ctx.error(Lang.t("Only the host of a network game can do this"))
			var name := Net.pardon(ctx.arg("tag"))
			return ctx.feedback(Lang.t("Unbanned %s") % name) if name != "" else ctx.error(Lang.t("No such ban")))))
